"""End-to-end API workflows on PostgreSQL with Row-Level Security active.

These cover the Phase 4-6 transactional paths (CSV import, forecasting
persistence, purchase-order receipts with row locks, alert evaluation) on the
real database, where RLS policies and ``SELECT ... FOR UPDATE`` apply.
"""

from __future__ import annotations

from datetime import date, timedelta

import pytest

from tests.helpers import auth_header, register_org, tokens_from

pytestmark = pytest.mark.postgres


def _org(client, name: str, email: str):
    reg = register_org(client, organization_name=name, email=email)
    assert reg.status_code == 201, reg.text
    return auth_header(tokens_from(reg)["access_token"])


def _catalogue(client, headers):
    store = client.post("/api/v1/stores", headers=headers, json={"name": "Main"}).json()
    supplier = client.post(
        "/api/v1/suppliers", headers=headers, json={"name": "Vendor"}
    ).json()
    product = client.post(
        "/api/v1/products",
        headers=headers,
        json={
            "sku": "PG-1", "name": "Widget", "unit_cost": "2", "unit_price": "4",
            "supplier_id": supplier["id"],
        },
    ).json()
    return store, supplier, product


def _import_sales(client, headers, days=90):
    end = date.today() - timedelta(days=1)
    rows = "\n".join(
        f"PG-1,Main,{(end - timedelta(days=i)).isoformat()},{5 + (i % 7)}"
        for i in range(days)
    )
    resp = client.post(
        "/api/v1/imports",
        headers=headers,
        files={"file": ("s.csv", f"sku,store,sale_date,quantity\n{rows}\n", "text/csv")},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


def test_import_forecast_and_isolation_on_postgres(pg_client):
    headers = _org(pg_client, "PG Workflow A", "owner@pg-a.com")
    _catalogue(pg_client, headers)
    batch = _import_sales(pg_client, headers)
    assert batch["status"] == "completed" and batch["valid_rows"] == 90

    again = _import_sales(pg_client, headers, days=3)
    assert again["status"] == "failed" and again["duplicate_rows"] == 3

    cmp = pg_client.post(
        "/api/v1/models:backtest", headers=headers, json={"horizon": 7, "folds": 1}
    )
    assert cmp.status_code == 200, cmp.text
    assert len(cmp.json()["models"]) == 4
    generated = pg_client.post(
        "/api/v1/forecasts:generate", headers=headers, json={"horizon": 7}
    ).json()
    assert generated["total"] == 7

    other = _org(pg_client, "PG Workflow B", "owner@pg-b.com")
    assert pg_client.get("/api/v1/forecasts", headers=other).json()["total"] == 0
    assert pg_client.get("/api/v1/imports", headers=other).json()["total"] == 0
    assert pg_client.get(
        f"/api/v1/imports/{batch['id']}", headers=other
    ).status_code == 404


def test_purchase_order_receipt_and_rollback_on_postgres(pg_client):
    headers = _org(pg_client, "PG Workflow C", "owner@pg-c.com")
    store, supplier, product = _catalogue(pg_client, headers)
    po = pg_client.post(
        "/api/v1/purchase-orders",
        headers=headers,
        json={
            "supplier_id": supplier["id"], "store_id": store["id"],
            "items": [{"product_id": product["id"], "quantity_ordered": "10"}],
        },
    ).json()
    url = f"/api/v1/purchase-orders/{po['id']}"
    pg_client.post(f"{url}/submit", headers=headers)
    po = pg_client.post(f"{url}/approve", headers=headers).json()
    item_id = po["items"][0]["id"]

    rejected = pg_client.post(
        f"{url}/receive", headers=headers,
        json={"lines": [{"item_id": item_id, "quantity": "11"}]},
    )
    assert rejected.status_code == 422
    stock = pg_client.get("/api/v1/inventory", headers=headers).json()["items"][0]
    assert float(stock["quantity_on_hand"]) == 0

    done = pg_client.post(
        f"{url}/receive", headers=headers,
        json={"lines": [{"item_id": item_id, "quantity": "10"}]},
    ).json()
    assert done["status"] == "received"
    stock = pg_client.get("/api/v1/inventory", headers=headers).json()["items"][0]
    assert float(stock["quantity_on_hand"]) == 10
    ledger = pg_client.get("/api/v1/movements", headers=headers).json()
    assert ledger["total"] == 1

    other = _org(pg_client, "PG Workflow D", "owner@pg-d.com")
    assert pg_client.get(url, headers=other).status_code == 404


def test_alerts_and_replenishment_on_postgres(pg_client):
    headers = _org(pg_client, "PG Workflow E", "owner@pg-e.com")
    _catalogue(pg_client, headers)
    _import_sales(pg_client, headers, days=60)
    result = pg_client.post("/api/v1/alerts:evaluate", headers=headers, json={}).json()
    assert result["created"] >= 1  # zero stock with real demand -> stockout risk
    alerts = pg_client.get("/api/v1/alerts", headers=headers).json()["items"]
    assert alerts[0]["alert_type"] == "stockout_risk"
    assert alerts[0]["severity"] == "critical"
    repl = pg_client.get("/api/v1/replenishment", headers=headers).json()["items"][0]
    assert repl["needs_reorder"] is True and repl["recommended_qty"] > 0
    drafts = pg_client.post(
        "/api/v1/purchase-orders/from-recommendations",
        headers=headers,
        json={"store_id": repl["store_id"]},
    )
    assert drafts.status_code == 201, drafts.text
    assert len(drafts.json()["created"]) == 1
