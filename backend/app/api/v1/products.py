"""Product endpoints."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser, require_roles
from app.core.rbac import Role
from app.db.session import get_db
from app.models.user import User
from app.schemas.common import Page
from app.schemas.product import ProductCreate, ProductOut, ProductUpdate
from app.services import product_service

router = APIRouter(prefix="/products", tags=["products"])
ManagerUser = Annotated[User, Depends(require_roles(Role.OWNER, Role.ADMIN, Role.MANAGER))]


@router.get("", response_model=Page[ProductOut])
def list_products(
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    search: str | None = Query(default=None),
    is_active: bool | None = Query(default=None),
) -> Page[ProductOut]:
    items, total = product_service.list_products(
        db, org_id=user.org_id, limit=limit, offset=offset, search=search, is_active=is_active
    )
    return Page[ProductOut](
        items=[ProductOut.model_validate(i) for i in items],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.post("", response_model=ProductOut, status_code=status.HTTP_201_CREATED)
def create_product(
    payload: ProductCreate,
    user: ManagerUser,
    db: Annotated[Session, Depends(get_db)],
) -> ProductOut:
    item = product_service.create_product(
        db,
        org_id=user.org_id,
        sku=payload.sku,
        name=payload.name,
        category_id=payload.category_id,
        supplier_id=payload.supplier_id,
        unit=payload.unit,
        unit_cost=payload.unit_cost,
        unit_price=payload.unit_price,
        is_active=payload.is_active,
    )
    return ProductOut.model_validate(item)


@router.get("/{product_id}", response_model=ProductOut)
def get_product(
    product_id: uuid.UUID,
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> ProductOut:
    item = product_service.get_product(db, org_id=user.org_id, product_id=product_id)
    return ProductOut.model_validate(item)


@router.patch("/{product_id}", response_model=ProductOut)
def update_product(
    product_id: uuid.UUID,
    payload: ProductUpdate,
    user: ManagerUser,
    db: Annotated[Session, Depends(get_db)],
) -> ProductOut:
    item = product_service.update_product(
        db,
        org_id=user.org_id,
        product_id=product_id,
        sku=payload.sku,
        name=payload.name,
        category_id=payload.category_id,
        supplier_id=payload.supplier_id,
        unit=payload.unit,
        unit_cost=payload.unit_cost,
        unit_price=payload.unit_price,
        is_active=payload.is_active,
    )
    return ProductOut.model_validate(item)
