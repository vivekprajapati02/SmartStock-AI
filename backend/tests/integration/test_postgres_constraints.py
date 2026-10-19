"""PostgreSQL database-constraint integration tests."""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db.session import set_org_context
from app.models.catalog import Store
from app.models.inventory import Inventory, SalesHistory
from app.models.organization import Organization
from app.models.product import Product
from app.models.user import User

pytestmark = pytest.mark.postgres


def _organization(prefix: str) -> Organization:
    return Organization(
        id=uuid.uuid4(), name=f"{prefix} Org", slug=f"{prefix}-{uuid.uuid4().hex[:8]}", is_demo=True
    )


def _product(org_id: uuid.UUID, sku: str) -> Product:
    return Product(
        id=uuid.uuid4(), org_id=org_id, sku=sku, name=f"Product {sku}", unit="unit",
        unit_cost=1, unit_price=2, is_active=True,
    )


def test_product_sku_unique_per_org_but_shared_across_orgs(pg_db: Session):
    org_a = _organization("sku-a")
    org_b = _organization("sku-b")
    pg_db.add_all([org_a, org_b])
    pg_db.flush()

    set_org_context(pg_db, org_a.id)
    pg_db.add(_product(org_a.id, "DUP-SKU"))
    pg_db.flush()

    with pytest.raises(IntegrityError):
        with pg_db.begin_nested():
            pg_db.add(_product(org_a.id, "DUP-SKU"))
            pg_db.flush()

    # The same SKU is allowed in a different organisation.
    set_org_context(pg_db, org_b.id)
    pg_db.add(_product(org_b.id, "DUP-SKU"))
    pg_db.flush()


def test_inventory_unique_per_product_store(pg_db: Session):
    org = _organization("inv")
    pg_db.add(org)
    pg_db.flush()
    set_org_context(pg_db, org.id)

    product = _product(org.id, "INV-1")
    store = Store(id=uuid.uuid4(), org_id=org.id, name="Store")
    pg_db.add_all([product, store])
    pg_db.flush()

    pg_db.add(
        Inventory(
            id=uuid.uuid4(), org_id=org.id, product_id=product.id, store_id=store.id,
            quantity_on_hand=1, reorder_point=0, safety_stock=0, lead_time_days=7,
        )
    )
    pg_db.flush()

    with pytest.raises(IntegrityError):
        with pg_db.begin_nested():
            pg_db.add(
                Inventory(
                    id=uuid.uuid4(), org_id=org.id, product_id=product.id, store_id=store.id,
                    quantity_on_hand=2, reorder_point=0, safety_stock=0, lead_time_days=7,
                )
            )
            pg_db.flush()


def test_sales_history_unique_per_day(pg_db: Session):
    from datetime import date

    org = _organization("sales")
    pg_db.add(org)
    pg_db.flush()
    set_org_context(pg_db, org.id)

    product = _product(org.id, "SALES-1")
    store = Store(id=uuid.uuid4(), org_id=org.id, name="Store")
    pg_db.add_all([product, store])
    pg_db.flush()

    row = SalesHistory(
        id=uuid.uuid4(), org_id=org.id, product_id=product.id, store_id=store.id,
        sale_date=date(2026, 1, 1), quantity=5,
    )
    pg_db.add(row)
    pg_db.flush()

    with pytest.raises(IntegrityError):
        with pg_db.begin_nested():
            pg_db.add(
                SalesHistory(
                    id=uuid.uuid4(), org_id=org.id, product_id=product.id, store_id=store.id,
                    sale_date=date(2026, 1, 1), quantity=7,
                )
            )
            pg_db.flush()


def test_user_email_unique_per_org(pg_db: Session):
    org = _organization("users")
    pg_db.add(org)
    pg_db.flush()
    set_org_context(pg_db, org.id)

    pg_db.add(
        User(
            id=uuid.uuid4(), org_id=org.id, email="u@x-corp.com",
            hashed_password="hash", role="viewer", is_active=True,
        )
    )
    pg_db.flush()

    with pytest.raises(IntegrityError):
        with pg_db.begin_nested():
            pg_db.add(
                User(
                    id=uuid.uuid4(), org_id=org.id, email="u@x-corp.com",
                    hashed_password="hash", role="viewer", is_active=True,
                )
            )
            pg_db.flush()
