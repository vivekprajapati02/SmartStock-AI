"""Inventory and stock-movement endpoints."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser, require_roles
from app.core.rbac import Role
from app.db.session import get_db
from app.models.catalog import Store
from app.models.inventory import Inventory, StockMovement
from app.models.product import Product
from app.models.user import User
from app.schemas.common import Page
from app.schemas.inventory import (
    InventoryOut,
    InventorySettingsUpdate,
    MovementCreate,
    MovementOut,
)
from app.services import inventory_service

router = APIRouter(prefix="/inventory", tags=["inventory"])
ManagerUser = Annotated[User, Depends(require_roles(Role.OWNER, Role.ADMIN, Role.MANAGER))]


def _to_inventory_out(inventory: Inventory, product: Product, store: Store) -> InventoryOut:
    qty = inventory.quantity_on_hand
    value = qty * product.unit_cost
    return InventoryOut(
        id=inventory.id,
        org_id=inventory.org_id,
        product_id=inventory.product_id,
        store_id=inventory.store_id,
        sku=product.sku,
        product_name=product.name,
        store_name=store.name,
        unit_cost=product.unit_cost,
        quantity_on_hand=qty,
        reorder_point=inventory.reorder_point,
        safety_stock=inventory.safety_stock,
        lead_time_days=inventory.lead_time_days,
        inventory_value=value,
        is_low_stock=qty <= inventory.reorder_point and qty > 0,
        is_stockout=qty <= 0,
        updated_at=inventory.updated_at,
    )


def _to_movement_out(movement: StockMovement, product: Product, store: Store) -> MovementOut:
    return MovementOut(
        id=movement.id,
        org_id=movement.org_id,
        product_id=movement.product_id,
        store_id=movement.store_id,
        sku=product.sku,
        product_name=product.name,
        store_name=store.name,
        movement_type=movement.movement_type,
        quantity=movement.quantity,
        reference=movement.reference,
        note=movement.note,
        occurred_at=movement.occurred_at,
    )


@router.get("", response_model=Page[InventoryOut])
def list_inventory(
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    store_id: uuid.UUID | None = Query(default=None),
    low_stock: bool | None = Query(default=None),
    search: str | None = Query(default=None),
) -> Page[InventoryOut]:
    rows, total = inventory_service.list_inventory(
        db,
        org_id=user.org_id,
        limit=limit,
        offset=offset,
        store_id=store_id,
        low_stock=low_stock,
        search=search,
    )
    return Page[InventoryOut](
        items=[_to_inventory_out(inv, product, store) for inv, product, store in rows],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.get("/{inventory_id}", response_model=InventoryOut)
def get_inventory(
    inventory_id: uuid.UUID,
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> InventoryOut:
    inventory, product, store = inventory_service.get_inventory(
        db, org_id=user.org_id, inventory_id=inventory_id
    )
    return _to_inventory_out(inventory, product, store)


@router.patch("/{inventory_id}", response_model=InventoryOut)
def update_inventory(
    inventory_id: uuid.UUID,
    payload: InventorySettingsUpdate,
    user: ManagerUser,
    db: Annotated[Session, Depends(get_db)],
) -> InventoryOut:
    inventory, product, store = inventory_service.update_inventory_settings(
        db,
        org_id=user.org_id,
        inventory_id=inventory_id,
        reorder_point=payload.reorder_point,
        safety_stock=payload.safety_stock,
        lead_time_days=payload.lead_time_days,
    )
    return _to_inventory_out(inventory, product, store)


movements_router = APIRouter(prefix="/movements", tags=["inventory"])


@movements_router.post("", response_model=MovementOut, status_code=status.HTTP_201_CREATED)
def create_movement(
    payload: MovementCreate,
    user: ManagerUser,
    db: Annotated[Session, Depends(get_db)],
) -> MovementOut:
    movement, _inventory = inventory_service.record_movement(
        db,
        org_id=user.org_id,
        product_id=payload.product_id,
        store_id=payload.store_id,
        movement_type=payload.movement_type,
        quantity=payload.quantity,
        reference=payload.reference,
        note=payload.note,
    )
    product = db.get(Product, movement.product_id)
    store = db.get(Store, movement.store_id)
    assert product is not None and store is not None
    return _to_movement_out(movement, product, store)


@movements_router.get("", response_model=Page[MovementOut])
def list_movements(
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    product_id: uuid.UUID | None = Query(default=None),
    store_id: uuid.UUID | None = Query(default=None),
) -> Page[MovementOut]:
    rows, total = inventory_service.list_movements(
        db,
        org_id=user.org_id,
        limit=limit,
        offset=offset,
        product_id=product_id,
        store_id=store_id,
    )
    return Page[MovementOut](
        items=[_to_movement_out(m, p, s) for m, p, s in rows],
        total=total,
        limit=limit,
        offset=offset,
    )
