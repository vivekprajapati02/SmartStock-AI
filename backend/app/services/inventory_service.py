"""Inventory queries and transactional stock movements."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.errors import NotFoundError, UnprocessableError
from app.db.session import set_org_context
from app.models.catalog import Store
from app.models.enums import MovementType
from app.models.inventory import Inventory, StockMovement
from app.models.product import Product


def _ensure_org(db: Session, org_id: uuid.UUID) -> None:
    set_org_context(db, org_id)


def _get_or_create_inventory(
    db: Session, *, org_id: uuid.UUID, product_id: uuid.UUID, store_id: uuid.UUID
) -> Inventory:
    row = db.execute(
        select(Inventory).where(
            Inventory.org_id == org_id,
            Inventory.product_id == product_id,
            Inventory.store_id == store_id,
        )
    ).scalar_one_or_none()
    if row is not None:
        return row
    row = Inventory(
        id=uuid.uuid4(),
        org_id=org_id,
        product_id=product_id,
        store_id=store_id,
        quantity_on_hand=Decimal("0"),
    )
    db.add(row)
    db.flush()
    return row


def list_inventory(
    db: Session,
    *,
    org_id: uuid.UUID,
    limit: int,
    offset: int,
    store_id: uuid.UUID | None = None,
    low_stock: bool | None = None,
    search: str | None = None,
) -> tuple[list[tuple[Inventory, Product, Store]], int]:
    _ensure_org(db, org_id)
    filters = [Inventory.org_id == org_id]
    if store_id is not None:
        filters.append(Inventory.store_id == store_id)
    if low_stock:
        filters.append(Inventory.quantity_on_hand <= Inventory.reorder_point)
    if search:
        pattern = f"%{search.strip().lower()}%"
        filters.append(
            func.lower(Product.name).like(pattern) | func.lower(Product.sku).like(pattern)
        )

    base = (
        select(Inventory, Product, Store)
        .join(Product, Product.id == Inventory.product_id)
        .join(Store, Store.id == Inventory.store_id)
        .where(*filters)
    )
    total = int(
        db.execute(
            select(func.count())
            .select_from(Inventory)
            .join(Product, Product.id == Inventory.product_id)
            .join(Store, Store.id == Inventory.store_id)
            .where(*filters)
        ).scalar_one()
    )
    rows = db.execute(
        base.order_by(Product.sku, Store.name).limit(limit).offset(offset)
    ).all()
    return list(rows), total


def get_inventory(
    db: Session, *, org_id: uuid.UUID, inventory_id: uuid.UUID
) -> tuple[Inventory, Product, Store]:
    _ensure_org(db, org_id)
    row = db.execute(
        select(Inventory, Product, Store)
        .join(Product, Product.id == Inventory.product_id)
        .join(Store, Store.id == Inventory.store_id)
        .where(Inventory.id == inventory_id, Inventory.org_id == org_id)
    ).one_or_none()
    if row is None:
        raise NotFoundError("Inventory record not found.")
    return row


def update_inventory_settings(
    db: Session,
    *,
    org_id: uuid.UUID,
    inventory_id: uuid.UUID,
    reorder_point: Decimal | None,
    safety_stock: Decimal | None,
    lead_time_days: int | None,
) -> tuple[Inventory, Product, Store]:
    inventory, product, store = get_inventory(db, org_id=org_id, inventory_id=inventory_id)
    if reorder_point is not None:
        inventory.reorder_point = reorder_point
    if safety_stock is not None:
        inventory.safety_stock = safety_stock
    if lead_time_days is not None:
        inventory.lead_time_days = lead_time_days
    db.commit()
    db.refresh(inventory)
    return inventory, product, store


def record_movement(
    db: Session,
    *,
    org_id: uuid.UUID,
    product_id: uuid.UUID,
    store_id: uuid.UUID,
    movement_type: MovementType,
    quantity: Decimal,
    reference: str | None,
    note: str | None,
) -> tuple[StockMovement, Inventory]:
    """Write a stock movement and update on-hand quantity in one transaction."""
    _ensure_org(db, org_id)

    product = db.get(Product, product_id)
    if product is None or product.org_id != org_id:
        raise NotFoundError("Product not found.")
    store = db.get(Store, store_id)
    if store is None or store.org_id != org_id:
        raise NotFoundError("Store not found.")

    inventory = _get_or_create_inventory(
        db, org_id=org_id, product_id=product_id, store_id=store_id
    )

    if movement_type == MovementType.IN:
        delta = quantity
    elif movement_type == MovementType.OUT:
        delta = -quantity
        if inventory.quantity_on_hand + delta < 0:
            raise UnprocessableError("Insufficient stock for this outbound movement.")
    else:
        delta = quantity
        if inventory.quantity_on_hand + delta < 0:
            raise UnprocessableError("Adjustment would result in negative stock.")

    movement = StockMovement(
        id=uuid.uuid4(),
        org_id=org_id,
        product_id=product_id,
        store_id=store_id,
        movement_type=movement_type,
        quantity=quantity if movement_type != MovementType.ADJUST else delta,
        reference=reference,
        note=note,
        # Stamped in Python: the DB's now() is per-transaction (Postgres) or
        # per-second (SQLite), which makes the ledger order ambiguous.
        occurred_at=datetime.now(UTC),
    )
    inventory.quantity_on_hand = inventory.quantity_on_hand + delta
    db.add(movement)
    db.commit()
    db.refresh(movement)
    db.refresh(inventory)
    return movement, inventory


def list_movements(
    db: Session,
    *,
    org_id: uuid.UUID,
    limit: int,
    offset: int,
    product_id: uuid.UUID | None = None,
    store_id: uuid.UUID | None = None,
) -> tuple[list[tuple[StockMovement, Product, Store]], int]:
    _ensure_org(db, org_id)
    filters = [StockMovement.org_id == org_id]
    if product_id is not None:
        filters.append(StockMovement.product_id == product_id)
    if store_id is not None:
        filters.append(StockMovement.store_id == store_id)

    total = int(
        db.execute(select(func.count()).select_from(StockMovement).where(*filters)).scalar_one()
    )
    rows = db.execute(
        select(StockMovement, Product, Store)
        .join(Product, Product.id == StockMovement.product_id)
        .join(Store, Store.id == StockMovement.store_id)
        .where(*filters)
        # The id tiebreaker keeps LIMIT/OFFSET pages stable.
        .order_by(StockMovement.occurred_at.desc(), StockMovement.id.desc())
        .limit(limit)
        .offset(offset)
    ).all()
    return list(rows), total
