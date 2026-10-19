"""API tests for inventory listing and transactional stock movements."""

from __future__ import annotations

from tests.helpers import auth_header, register_org, tokens_from


def _setup(client):
    token = tokens_from(register_org(client))["access_token"]
    headers = auth_header(token)
    store = client.post("/api/v1/stores", headers=headers, json={"name": "Main"}).json()
    product = client.post(
        "/api/v1/products",
        headers=headers,
        json={"sku": "SKU-1", "name": "Widget", "unit_cost": "10.00", "unit_price": "20.00"},
    ).json()
    return headers, store, product


def test_product_creation_seeds_inventory_rows(client):
    headers, store, product = _setup(client)
    listed = client.get("/api/v1/inventory", headers=headers)
    assert listed.status_code == 200
    body = listed.json()
    assert body["total"] == 1
    row = body["items"][0]
    assert row["product_id"] == product["id"]
    assert row["store_id"] == store["id"]
    assert float(row["quantity_on_hand"]) == 0


def test_inbound_movement_increases_stock(client):
    headers, store, product = _setup(client)
    movement = client.post(
        "/api/v1/movements",
        headers=headers,
        json={
            "product_id": product["id"],
            "store_id": store["id"],
            "movement_type": "in",
            "quantity": "25",
            "reference": "PO-1",
        },
    )
    assert movement.status_code == 201, movement.text
    listed = client.get("/api/v1/inventory", headers=headers).json()["items"][0]
    assert float(listed["quantity_on_hand"]) == 25
    assert float(listed["inventory_value"]) == 250


def test_outbound_movement_cannot_go_negative(client):
    headers, store, product = _setup(client)
    client.post(
        "/api/v1/movements",
        headers=headers,
        json={
            "product_id": product["id"],
            "store_id": store["id"],
            "movement_type": "in",
            "quantity": "5",
        },
    )
    failed = client.post(
        "/api/v1/movements",
        headers=headers,
        json={
            "product_id": product["id"],
            "store_id": store["id"],
            "movement_type": "out",
            "quantity": "9",
        },
    )
    assert failed.status_code == 422
    listed = client.get("/api/v1/inventory", headers=headers).json()["items"][0]
    assert float(listed["quantity_on_hand"]) == 5


def test_adjust_and_list_movements(client):
    headers, store, product = _setup(client)
    client.post(
        "/api/v1/movements",
        headers=headers,
        json={
            "product_id": product["id"],
            "store_id": store["id"],
            "movement_type": "in",
            "quantity": "10",
        },
    )
    adjust = client.post(
        "/api/v1/movements",
        headers=headers,
        json={
            "product_id": product["id"],
            "store_id": store["id"],
            "movement_type": "adjust",
            "quantity": "-2",
            "note": "count correction",
        },
    )
    assert adjust.status_code == 201, adjust.text
    listed = client.get("/api/v1/inventory", headers=headers).json()["items"][0]
    assert float(listed["quantity_on_hand"]) == 8
    movements = client.get("/api/v1/movements", headers=headers)
    assert movements.status_code == 200
    assert movements.json()["total"] == 2


def test_movement_ledger_is_newest_first(client):
    headers, store, product = _setup(client)
    for movement_type, quantity in (("in", "10"), ("out", "3"), ("adjust", "-1")):
        created = client.post(
            "/api/v1/movements",
            headers=headers,
            json={
                "product_id": product["id"],
                "store_id": store["id"],
                "movement_type": movement_type,
                "quantity": quantity,
            },
        )
        assert created.status_code == 201, created.text
    items = client.get("/api/v1/movements", headers=headers).json()["items"]
    assert [m["movement_type"] for m in items] == ["adjust", "out", "in"]
    first_page = client.get("/api/v1/movements?limit=2", headers=headers).json()["items"]
    second_page = client.get(
        "/api/v1/movements?limit=2&offset=2", headers=headers
    ).json()["items"]
    assert [m["id"] for m in first_page + second_page] == [m["id"] for m in items]


def test_inventory_is_org_scoped(client):
    headers_a, _store, _product = _setup(client)
    token_b = tokens_from(
        register_org(
            client,
            organization_name="Beta Inc",
            organization_slug="beta",
            email="owner@beta-corp.com",
        )
    )["access_token"]
    listed_b = client.get("/api/v1/inventory", headers=auth_header(token_b))
    assert listed_b.status_code == 200
    assert listed_b.json()["total"] == 0
    listed_a = client.get("/api/v1/inventory", headers=headers_a)
    assert listed_a.json()["total"] == 1
