"""Unit tests for transactional inventory updates (SQLite)."""

from __future__ import annotations

import uuid
from decimal import Decimal

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.errors import UnprocessableError
from app.db.session import set_org_context
from app.models.catalog import Store
from app.models.enums import MovementType
from app.models.inventory import Inventory
from app.models.organization import Organization
from app.models.product import Product
from app.services import inventory_service


def _org_product_store(db: Session) -> tuple[uuid.UUID, uuid.UUID, uuid.UUID]:
    org = Organization(
        id=uuid.uuid4(),
        name=f"Org {uuid.uuid4().hex[:6]}",
        slug=f"o-{uuid.uuid4().hex[:8]}",
    )
    db.add(org)
    db.flush()
    set_org_context(db, org.id)
    product = Product(
        id=uuid.uuid4(),
        org_id=org.id,
        sku="SKU-T",
        name="Widget",
        unit="unit",
        unit_cost=1,
        unit_price=2,
    )
    store = Store(id=uuid.uuid4(), org_id=org.id, name="S1")
    db.add_all([product, store])
    db.flush()
    return org.id, product.id, store.id


def test_failed_outbound_does_not_change_stock(db: Session):
    org_id, product_id, store_id = _org_product_store(db)
    inventory_service.record_movement(
        db,
        org_id=org_id,
        product_id=product_id,
        store_id=store_id,
        movement_type=MovementType.IN,
        quantity=Decimal("4"),
        reference=None,
        note=None,
    )
    with pytest.raises(UnprocessableError):
        inventory_service.record_movement(
            db,
            org_id=org_id,
            product_id=product_id,
            store_id=store_id,
            movement_type=MovementType.OUT,
            quantity=Decimal("9"),
            reference=None,
            note=None,
        )
    row = db.execute(select(Inventory).where(Inventory.product_id == product_id)).scalar_one()
    assert row.quantity_on_hand == Decimal("4")
