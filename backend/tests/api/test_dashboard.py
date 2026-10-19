"""Dashboard metrics are computed from stored data, never hardcoded."""

from __future__ import annotations

import uuid
from datetime import date
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import set_org_context
from app.models.inventory import SalesHistory
from app.models.user import User
from tests.helpers import auth_header, register_org, tokens_from


def test_empty_org_dashboard_is_zero(client):
    token = tokens_from(register_org(client))["access_token"]
    response = client.get("/api/v1/analytics/dashboard", headers=auth_header(token))
    assert response.status_code == 200, response.text
    body = response.json()
    assert float(body["inventory_value"]) == 0
    assert body["sku_count"] == 0
    assert body["store_count"] == 0
    assert body["low_stock_count"] == 0
    assert body["stockout_count"] == 0
    assert body["pending_order_count"] == 0
    assert len(body["demand_trend"]) == 30
    assert all(float(point["quantity"]) == 0 for point in body["demand_trend"])
    assert body["is_demo"] is False


def test_dashboard_reflects_real_inventory_and_sales(client, db: Session):
    token = tokens_from(register_org(client))["access_token"]
    headers = auth_header(token)
    store = client.post("/api/v1/stores", headers=headers, json={"name": "Main"}).json()
    product = client.post(
        "/api/v1/products",
        headers=headers,
        json={"sku": "SKU-1", "name": "Widget", "unit_cost": "4.00", "unit_price": "9.00"},
    ).json()
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

    user = db.execute(select(User).where(User.email == "owner@acme-corp.com")).scalar_one()
    set_org_context(db, user.org_id)
    db.add(
        SalesHistory(
            org_id=user.org_id,
            product_id=uuid.UUID(product["id"]),
            store_id=uuid.UUID(store["id"]),
            sale_date=date.today(),
            quantity=Decimal("7"),
        )
    )
    db.commit()

    response = client.get("/api/v1/analytics/dashboard", headers=headers)
    assert response.status_code == 200, response.text
    body = response.json()
    assert float(body["inventory_value"]) == 40
    assert body["sku_count"] == 1
    assert body["store_count"] == 1
    today_qty = next(
        point["quantity"]
        for point in body["demand_trend"]
        if point["sale_date"] == date.today().isoformat()
    )
    assert float(today_qty) == 7


def test_dashboard_is_org_scoped(client):
    token_a = tokens_from(register_org(client))["access_token"]
    headers_a = auth_header(token_a)
    store = client.post("/api/v1/stores", headers=headers_a, json={"name": "Main"}).json()
    product = client.post(
        "/api/v1/products",
        headers=headers_a,
        json={"sku": "SKU-1", "name": "Widget", "unit_cost": "5.00"},
    ).json()
    client.post(
        "/api/v1/movements",
        headers=headers_a,
        json={
            "product_id": product["id"],
            "store_id": store["id"],
            "movement_type": "in",
            "quantity": "8",
        },
    )

    token_b = tokens_from(
        register_org(
            client,
            organization_name="Beta Inc",
            organization_slug="beta",
            email="owner@beta-corp.com",
        )
    )["access_token"]
    dash_b = client.get("/api/v1/analytics/dashboard", headers=auth_header(token_b)).json()
    dash_a = client.get("/api/v1/analytics/dashboard", headers=headers_a).json()
    assert float(dash_b["inventory_value"]) == 0
    assert dash_b["sku_count"] == 0
    assert float(dash_a["inventory_value"]) == 40
