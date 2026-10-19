"""API tests for catalogue CRUD and tenant isolation (SQLite)."""

from __future__ import annotations

from tests.helpers import auth_header, register_org, tokens_from


def _owner(client, name="Acme Corp", slug="acme-corp", email="owner@acme-corp.com"):
    return tokens_from(
        register_org(client, organization_name=name, organization_slug=slug, email=email)
    )["access_token"]


def test_category_crud(client):
    token = _owner(client)
    created = client.post("/api/v1/categories", headers=auth_header(token), json={"name": "Dairy"})
    assert created.status_code == 201, created.text
    category_id = created.json()["id"]

    listed = client.get("/api/v1/categories", headers=auth_header(token))
    assert listed.status_code == 200
    assert listed.json()["total"] == 1

    fetched = client.get(f"/api/v1/categories/{category_id}", headers=auth_header(token))
    assert fetched.status_code == 200
    assert fetched.json()["name"] == "Dairy"

    updated = client.patch(
        f"/api/v1/categories/{category_id}",
        headers=auth_header(token),
        json={"name": "Beverages"},
    )
    assert updated.status_code == 200
    assert updated.json()["name"] == "Beverages"


def test_category_duplicate_name_conflicts(client):
    token = _owner(client)
    created = client.post(
        "/api/v1/categories", headers=auth_header(token), json={"name": "Snacks"}
    )
    assert created.status_code == 201
    duplicate = client.post(
        "/api/v1/categories", headers=auth_header(token), json={"name": "Snacks"}
    )
    assert duplicate.status_code == 409


def test_supplier_and_store_crud(client):
    token = _owner(client)
    supplier = client.post(
        "/api/v1/suppliers",
        headers=auth_header(token),
        json={"name": "Northwind", "lead_time_days": 5},
    )
    assert supplier.status_code == 201, supplier.text
    store = client.post(
        "/api/v1/stores",
        headers=auth_header(token),
        json={"name": "Store 1", "location": "Downtown"},
    )
    assert store.status_code == 201, store.text
    assert store.json()["location"] == "Downtown"


def test_product_crud_and_sku_unique(client):
    token = _owner(client)
    created = client.post(
        "/api/v1/products",
        headers=auth_header(token),
        json={"sku": "SKU-1", "name": "Widget", "unit_cost": "2.50", "unit_price": "5.00"},
    )
    assert created.status_code == 201, created.text
    duplicate = client.post(
        "/api/v1/products",
        headers=auth_header(token),
        json={"sku": "SKU-1", "name": "Other"},
    )
    assert duplicate.status_code == 409


def test_catalog_is_org_scoped(client):
    token_a = _owner(client, name="Alpha Inc", slug="alpha", email="owner@alpha-corp.com")
    token_b = _owner(client, name="Beta Inc", slug="beta", email="owner@beta-corp.com")
    created = client.post(
        "/api/v1/categories", headers=auth_header(token_a), json={"name": "Secret"}
    )
    assert created.status_code == 201
    category_id = created.json()["id"]

    listed_b = client.get("/api/v1/categories", headers=auth_header(token_b))
    assert listed_b.json()["total"] == 0

    missing = client.get(f"/api/v1/categories/{category_id}", headers=auth_header(token_b))
    assert missing.status_code == 404


def test_unauthenticated_catalog_is_rejected(client):
    response = client.get("/api/v1/products")
    assert response.status_code == 401
