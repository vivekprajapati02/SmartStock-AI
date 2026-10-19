"""API tests for replenishment, alerts and purchase orders."""

from __future__ import annotations

import math
import uuid
from datetime import date, timedelta
from statistics import NormalDist

import pytest
from sqlalchemy import select

from app.models.inventory import SalesHistory, StockMovement
from tests.helpers import USERS_URL, auth_header, login, register_org, tokens_from

Z95 = NormalDist().inv_cdf(0.95)
END = date.today() - timedelta(days=1)


def _org(client, name="Acme Corp", email="owner@acme-corp.com"):
    reg = register_org(client, organization_name=name, email=email)
    return auth_header(tokens_from(reg)["access_token"]), uuid.UUID(reg.json()["user"]["org_id"])


def _setup(client, *, with_supplier=True, products=1):
    headers, org_id = _org(client)
    store = client.post("/api/v1/stores", headers=headers, json={"name": "Main"}).json()
    supplier = None
    if with_supplier:
        supplier = client.post(
            "/api/v1/suppliers", headers=headers, json={"name": "Supplier A", "lead_time_days": 5}
        ).json()
    made = []
    for i in range(products):
        made.append(client.post(
            "/api/v1/products",
            headers=headers,
            json={
                "sku": f"SKU-{i}",
                "name": f"Item {i}",
                "unit_cost": "2.50",
                "unit_price": "5",
                "supplier_id": supplier["id"] if supplier else None,
            },
        ).json())
    return headers, org_id, store, supplier, made


def _inventory(client, headers, product_id):
    rows = client.get("/api/v1/inventory", headers=headers).json()["items"]
    return next(r for r in rows if r["product_id"] == product_id)


def _stock_in(client, headers, product, store, qty):
    resp = client.post(
        "/api/v1/movements",
        headers=headers,
        json={
            "product_id": product["id"], "store_id": store["id"],
            "movement_type": "in", "quantity": str(qty),
        },
    )
    assert resp.status_code == 201, resp.text


def _sales(db, org_id, product, store, values, end=END):
    for i, qty in enumerate(values):
        db.add(SalesHistory(
            org_id=org_id,
            product_id=uuid.UUID(product["id"]),
            store_id=uuid.UUID(store["id"]),
            sale_date=end - timedelta(days=len(values) - 1 - i),
            quantity=qty,
        ))
    db.flush()


def _user(client, owner_headers, email, role):
    client.post(
        USERS_URL,
        headers=owner_headers,
        json={"email": email, "password": "password-123", "role": role},
    )
    return auth_header(tokens_from(login(client, email=email))["access_token"])


# ---------------------------------------------------------------- replenishment


def test_replenishment_matches_hand_computed_values(client, db):
    headers, org_id, store, _, (product,) = _setup(client)
    _sales(db, org_id, product, store, [4, 6] * 28)  # 56 days: mean 5
    _stock_in(client, headers, product, store, 10)

    body = client.get("/api/v1/replenishment", headers=headers).json()
    item = body["items"][0]
    std = math.sqrt(56 / 55)  # sample std of alternating 4/6
    safety = Z95 * std * math.sqrt(7)
    assert body["z_score"] == pytest.approx(Z95, abs=1e-4)
    assert body["history_end"] == END.isoformat()
    assert item["demand_source"] == "history"
    assert item["avg_daily_demand"] == pytest.approx(5)
    assert item["demand_std"] == pytest.approx(std, abs=1e-3)
    assert item["lead_time_days"] == 7
    assert item["lead_time_demand"] == pytest.approx(35)
    assert item["safety_stock"] == pytest.approx(safety, abs=1e-3)
    assert item["reorder_point"] == pytest.approx(35 + safety, abs=1e-3)
    assert item["target_stock"] == pytest.approx(70 + safety, abs=1e-3)
    assert item["recommended_qty"] == math.ceil(70 + safety - 10)
    assert item["needs_reorder"] is True
    assert item["days_of_cover"] == pytest.approx(2)
    assert item["supplier_name"] == "Supplier A"


def test_open_purchase_orders_count_toward_position(client, db):
    headers, org_id, store, supplier, (product,) = _setup(client)
    _sales(db, org_id, product, store, [5] * 56)  # std 0 -> no safety stock
    _stock_in(client, headers, product, store, 10)
    po = client.post(
        "/api/v1/purchase-orders",
        headers=headers,
        json={
            "supplier_id": supplier["id"], "store_id": store["id"],
            "items": [{"product_id": product["id"], "quantity_ordered": "30"}],
        },
    ).json()
    item = client.get("/api/v1/replenishment", headers=headers).json()["items"][0]
    assert item["on_order"] == 0  # drafts are not on order yet
    client.post(f"/api/v1/purchase-orders/{po['id']}/submit", headers=headers)
    item = client.get("/api/v1/replenishment", headers=headers).json()["items"][0]
    assert item["on_order"] == 30
    assert item["inventory_position"] == 40
    assert item["reorder_point"] == 35
    assert item["needs_reorder"] is False  # 40 > ROP 35
    assert item["recommended_qty"] == 0


def test_no_sales_history_gives_zero_recommendations(client):
    headers, _, _, _, _ = _setup(client)
    item = client.get("/api/v1/replenishment", headers=headers).json()["items"][0]
    assert item["demand_source"] == "none"
    assert item["reorder_point"] == 0 and item["recommended_qty"] == 0
    assert item["days_of_cover"] is None


def test_apply_writes_computed_settings(client, db):
    headers, org_id, store, _, (product,) = _setup(client)
    _sales(db, org_id, product, store, [5] * 56)
    resp = client.post("/api/v1/replenishment/apply", headers=headers, json={})
    assert resp.json() == {"updated": 1}
    inv = _inventory(client, headers, product["id"])
    assert float(inv["reorder_point"]) == 35
    assert float(inv["safety_stock"]) == 0


# ---------------------------------------------------------------- alerts


def test_alert_lifecycle_create_dedupe_resolve(client, db):
    headers, org_id, store, _, (product,) = _setup(client)
    _sales(db, org_id, product, store, [5] * 56)
    _stock_in(client, headers, product, store, 3)
    inv = _inventory(client, headers, product["id"])
    client.patch(
        f"/api/v1/inventory/{inv['id']}",
        headers=headers,
        json={"reorder_point": "20", "safety_stock": "5"},
    )

    first = client.post("/api/v1/alerts:evaluate", headers=headers, json={}).json()
    alerts = client.get("/api/v1/alerts", headers=headers).json()["items"]
    types = {a["alert_type"]: a for a in alerts}
    assert set(types) == {"low_stock", "stockout_risk"}
    assert types["low_stock"]["severity"] == "high"  # 3 <= safety stock 5
    assert "reorder point 20" in types["low_stock"]["message"]
    assert types["stockout_risk"]["severity"] == "high"
    assert first["created"] == 2 and first["open_total"] == 2
    # Most severe first.
    assert [a["severity"] for a in alerts] == sorted(
        [a["severity"] for a in alerts], key=["critical", "high", "medium", "low"].index
    )

    again = client.post("/api/v1/alerts:evaluate", headers=headers, json={}).json()
    assert (again["created"], again["updated"], again["resolved"]) == (0, 0, 0)

    _stock_in(client, headers, product, store, 100)
    after = client.post("/api/v1/alerts:evaluate", headers=headers, json={}).json()
    assert after["resolved"] == 2
    open_alerts = client.get("/api/v1/alerts?status=open", headers=headers).json()
    assert open_alerts["total"] == 0


def test_dismissed_alert_is_not_reopened(client, db):
    headers, org_id, store, _, (product,) = _setup(client)
    _sales(db, org_id, product, store, [5] * 56)  # on hand 0 -> stockout risk
    client.post("/api/v1/alerts:evaluate", headers=headers, json={})
    alert = client.get("/api/v1/alerts", headers=headers).json()["items"][0]
    assert alert["alert_type"] == "stockout_risk" and alert["severity"] == "critical"
    resp = client.patch(
        f"/api/v1/alerts/{alert['id']}", headers=headers, json={"status": "dismissed"}
    )
    assert resp.json()["status"] == "dismissed"
    result = client.post("/api/v1/alerts:evaluate", headers=headers, json={}).json()
    assert result["created"] == 0 and result["open_total"] == 0


def test_overstock_and_slow_moving(client, db):
    headers, org_id, store, _, products = _setup(client, products=2)
    fast, idle = products
    _sales(db, org_id, fast, store, [1] * 56)
    _sales(db, org_id, idle, store, [2] * 20 + [0] * 36)  # nothing in last 30 days
    _stock_in(client, headers, fast, store, 500)  # 500 days of cover
    _stock_in(client, headers, idle, store, 10)
    client.post("/api/v1/alerts:evaluate", headers=headers, json={})
    alerts = client.get("/api/v1/alerts", headers=headers).json()["items"]
    by = {(a["sku"], a["alert_type"]): a for a in alerts}
    assert by[("SKU-0", "overstock")]["severity"] == "medium"  # > 2 x 60 days
    assert ("SKU-1", "slow_moving") in by
    assert ("SKU-0", "slow_moving") not in by


def test_dashboard_counts_open_alerts(client, db):
    headers, org_id, store, _, (product,) = _setup(client)
    assert client.get("/api/v1/analytics/dashboard", headers=headers).json()[
        "open_alert_count"
    ] == 0
    _sales(db, org_id, product, store, [5] * 56)
    client.post("/api/v1/alerts:evaluate", headers=headers, json={})
    assert client.get("/api/v1/analytics/dashboard", headers=headers).json()[
        "open_alert_count"
    ] == 1


# ---------------------------------------------------------------- purchase orders


def _po(client, headers, supplier, store, lines):
    resp = client.post(
        "/api/v1/purchase-orders",
        headers=headers,
        json={
            "supplier_id": supplier["id"],
            "store_id": store["id"],
            "reference": "PO-1001",
            "items": [{"product_id": p["id"], "quantity_ordered": str(q)} for p, q in lines],
        },
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


def test_purchase_order_full_lifecycle_with_partial_receipt(client, db):
    headers, _, store, supplier, products = _setup(client, products=2)
    a, b = products
    po = _po(client, headers, supplier, store, [(a, 10), (b, 4)])
    assert po["status"] == "draft"
    assert float(po["estimated_cost"]) == 35.0  # 14 x 2.50
    assert po["line_count"] == 2

    po = client.post(f"/api/v1/purchase-orders/{po['id']}/submit", headers=headers).json()
    assert po["status"] == "pending"
    po = client.post(f"/api/v1/purchase-orders/{po['id']}/approve", headers=headers).json()
    assert po["status"] == "approved" and po["approved_by"] is not None

    lines = {i["sku"]: i for i in po["items"]}
    partial = client.post(
        f"/api/v1/purchase-orders/{po['id']}/receive",
        headers=headers,
        json={"lines": [{"item_id": lines["SKU-0"]["id"], "quantity": "6"}], "note": "first truck"},
    ).json()
    assert partial["status"] == "partial"
    assert float(_inventory(client, headers, a["id"])["quantity_on_hand"]) == 6
    assert {i["sku"]: float(i["quantity_remaining"]) for i in partial["items"]} == {
        "SKU-0": 4, "SKU-1": 4,
    }

    done = client.post(
        f"/api/v1/purchase-orders/{po['id']}/receive",
        headers=headers,
        json={"lines": [
            {"item_id": lines["SKU-0"]["id"], "quantity": "4"},
            {"item_id": lines["SKU-1"]["id"], "quantity": "4"},
        ]},
    ).json()
    assert done["status"] == "received"
    assert float(_inventory(client, headers, a["id"])["quantity_on_hand"]) == 10
    assert float(_inventory(client, headers, b["id"])["quantity_on_hand"]) == 4

    movements = db.execute(
        select(StockMovement).where(StockMovement.reference == "PO-1001")
    ).scalars().all()
    assert len(movements) == 3
    assert all(m.movement_type.value == "in" for m in movements)
    assert sorted(float(m.quantity) for m in movements) == [4, 4, 6]

    again = client.post(
        f"/api/v1/purchase-orders/{po['id']}/receive",
        headers=headers,
        json={"lines": [{"item_id": lines["SKU-0"]["id"], "quantity": "1"}]},
    )
    assert again.status_code == 409


def test_over_receipt_rolls_back_the_whole_receipt(client, db):
    headers, _, store, supplier, products = _setup(client, products=2)
    a, b = products
    po = _po(client, headers, supplier, store, [(a, 10), (b, 4)])
    client.post(f"/api/v1/purchase-orders/{po['id']}/submit", headers=headers)
    po = client.post(f"/api/v1/purchase-orders/{po['id']}/approve", headers=headers).json()
    lines = {i["sku"]: i for i in po["items"]}
    resp = client.post(
        f"/api/v1/purchase-orders/{po['id']}/receive",
        headers=headers,
        json={"lines": [
            {"item_id": lines["SKU-0"]["id"], "quantity": "5"},   # valid
            {"item_id": lines["SKU-1"]["id"], "quantity": "9"},   # exceeds 4
        ]},
    )
    assert resp.status_code == 422
    assert "only 4" in resp.json()["error"]["message"]
    assert float(_inventory(client, headers, a["id"])["quantity_on_hand"]) == 0
    detail = client.get(f"/api/v1/purchase-orders/{po['id']}", headers=headers).json()
    assert detail["status"] == "approved"
    assert all(float(i["quantity_received"]) == 0 for i in detail["items"])
    assert db.execute(select(StockMovement)).scalars().all() == []


def test_invalid_transitions_and_draft_only_edits(client):
    headers, _, store, supplier, (product,) = _setup(client)
    po = _po(client, headers, supplier, store, [(product, 3)])
    url = f"/api/v1/purchase-orders/{po['id']}"
    assert client.post(f"{url}/approve", headers=headers).status_code == 409
    assert client.post(
        f"{url}/receive", headers=headers,
        json={"lines": [{"item_id": po["items"][0]["id"], "quantity": "1"}]},
    ).status_code == 409

    edited = client.patch(
        url, headers=headers,
        json={
            "reference": "PO-EDIT",
            "items": [{"product_id": product["id"], "quantity_ordered": "8"}],
        },
    ).json()
    assert edited["reference"] == "PO-EDIT"
    assert float(edited["total_ordered"]) == 8 and edited["line_count"] == 1

    client.post(f"{url}/submit", headers=headers)
    assert client.patch(url, headers=headers, json={"reference": "x"}).status_code == 409
    cancelled = client.post(f"{url}/cancel", headers=headers).json()
    assert cancelled["status"] == "cancelled"
    assert client.post(f"{url}/cancel", headers=headers).status_code == 409


def test_po_validation(client):
    headers, _, store, supplier, (product,) = _setup(client)
    dup = client.post(
        "/api/v1/purchase-orders", headers=headers,
        json={"supplier_id": supplier["id"], "store_id": store["id"], "items": [
            {"product_id": product["id"], "quantity_ordered": "1"},
            {"product_id": product["id"], "quantity_ordered": "2"},
        ]},
    )
    assert dup.status_code == 422
    zero = client.post(
        "/api/v1/purchase-orders", headers=headers,
        json={"supplier_id": supplier["id"], "store_id": store["id"],
              "items": [{"product_id": product["id"], "quantity_ordered": "0"}]},
    )
    assert zero.status_code == 422
    unknown = client.post(
        "/api/v1/purchase-orders", headers=headers,
        json={"supplier_id": str(uuid.uuid4()), "store_id": store["id"],
              "items": [{"product_id": product["id"], "quantity_ordered": "1"}]},
    )
    assert unknown.status_code == 404


def test_only_admins_approve_and_viewers_read(client):
    headers, _, store, supplier, (product,) = _setup(client)
    manager = _user(client, headers, "manager@acme-corp.com", "manager")
    viewer = _user(client, headers, "viewer@acme-corp.com", "viewer")
    po = _po(client, manager, supplier, store, [(product, 2)])
    url = f"/api/v1/purchase-orders/{po['id']}"
    assert client.post(f"{url}/submit", headers=manager).json()["status"] == "pending"
    assert client.post(f"{url}/approve", headers=manager).status_code == 403
    assert client.post(f"{url}/approve", headers=headers).json()["status"] == "approved"
    assert client.get(url, headers=viewer).status_code == 200
    assert client.post(f"{url}/cancel", headers=viewer).status_code == 403
    assert client.post("/api/v1/alerts:evaluate", headers=viewer, json={}).status_code == 403
    assert client.get("/api/v1/replenishment", headers=viewer).status_code == 200


def test_orders_from_recommendations_group_by_supplier(client, db):
    headers, org_id, store, supplier, products = _setup(client, products=2)
    orphan = client.post(
        "/api/v1/products", headers=headers,
        json={"sku": "NOSUP", "name": "No supplier", "unit_cost": "1", "unit_price": "1"},
    ).json()
    for p in (*products, orphan):
        _sales(db, org_id, p, store, [5] * 56)
    resp = client.post(
        "/api/v1/purchase-orders/from-recommendations",
        headers=headers,
        json={"store_id": store["id"]},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert len(body["created"]) == 1
    order = body["created"][0]
    assert order["supplier_id"] == supplier["id"] and order["status"] == "draft"
    assert order["line_count"] == 2
    assert float(order["total_ordered"]) == 140  # 2 x (70 target - 0 position)
    assert [s["sku"] for s in body["skipped"]] == ["NOSUP"]


def test_planning_is_org_scoped(client, db):
    headers, _, store, supplier, (product,) = _setup(client)
    po = _po(client, headers, supplier, store, [(product, 1)])
    other, _ = _org(client, name="Beta Corp", email="owner@beta-corp.com")
    assert client.get(f"/api/v1/purchase-orders/{po['id']}", headers=other).status_code == 404
    assert client.post(
        f"/api/v1/purchase-orders/{po['id']}/submit", headers=other
    ).status_code == 404
    assert client.get("/api/v1/purchase-orders", headers=other).json()["total"] == 0
    assert client.get("/api/v1/replenishment", headers=other).json()["total"] == 0
    bad = client.post(
        "/api/v1/purchase-orders", headers=other,
        json={"supplier_id": supplier["id"], "store_id": store["id"],
              "items": [{"product_id": product["id"], "quantity_ordered": "1"}]},
    )
    assert bad.status_code == 404
