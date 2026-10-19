"""Database constraint tests that also run on the fast SQLite path."""

from __future__ import annotations

import uuid
from datetime import date

import pytest
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.catalog import Store
from app.models.inventory import Inventory, SalesHistory
from app.models.organization import Organization
from app.models.product import Product
from app.models.user import User


def _org(db: Session) -> Organization:
    org = Organization(
        id=uuid.uuid4(),
        name=f"Org {uuid.uuid4().hex[:6]}",
        slug=f"o-{uuid.uuid4().hex[:8]}",
    )
    db.add(org)
    db.flush()
    return org


def _product(org_id: uuid.UUID, sku: str) -> Product:
    return Product(
        id=uuid.uuid4(), org_id=org_id, sku=sku, name=sku, unit="unit", unit_cost=0, unit_price=0
    )


def _store(org_id: uuid.UUID, name: str) -> Store:
    return Store(id=uuid.uuid4(), org_id=org_id, name=name)


def _inventory(
    org_id: uuid.UUID, product_id: uuid.UUID, store_id: uuid.UUID, qty: int
) -> Inventory:
    return Inventory(
        id=uuid.uuid4(),
        org_id=org_id,
        product_id=product_id,
        store_id=store_id,
        quantity_on_hand=qty,
    )


def _sales(
    org_id: uuid.UUID, product_id: uuid.UUID, store_id: uuid.UUID, qty: int
) -> SalesHistory:
    return SalesHistory(
        id=uuid.uuid4(),
        org_id=org_id,
        product_id=product_id,
        store_id=store_id,
        sale_date=date(2026, 1, 1),
        quantity=qty,
    )


def _user(org_id: uuid.UUID, email: str) -> User:
    return User(
        id=uuid.uuid4(),
        org_id=org_id,
        email=email,
        hashed_password="h",
        role="viewer",
        is_active=True,
    )


def test_product_sku_unique_per_org(db: Session):
    org = _org(db)
    db.add(_product(org.id, "SKU-X"))
    db.flush()
    with pytest.raises(IntegrityError):
        db.add(_product(org.id, "SKU-X"))
        db.flush()


def test_inventory_unique_per_product_store(db: Session):
    org = _org(db)
    product = _product(org.id, "SKU-INV")
    store = _store(org.id, "S1")
    db.add_all([product, store])
    db.flush()
    db.add(_inventory(org.id, product.id, store.id, 1))
    db.flush()
    with pytest.raises(IntegrityError):
        db.add(_inventory(org.id, product.id, store.id, 2))
        db.flush()


def test_sales_history_unique_per_day(db: Session):
    org = _org(db)
    product = _product(org.id, "SKU-SALE")
    store = _store(org.id, "S2")
    db.add_all([product, store])
    db.flush()
    db.add(_sales(org.id, product.id, store.id, 1))
    db.flush()
    with pytest.raises(IntegrityError):
        db.add(_sales(org.id, product.id, store.id, 2))
        db.flush()


def test_user_email_unique_per_org(db: Session):
    org = _org(db)
    db.add(_user(org.id, "a@b.com"))
    db.flush()
    with pytest.raises(IntegrityError):
        db.add(_user(org.id, "a@b.com"))
        db.flush()
