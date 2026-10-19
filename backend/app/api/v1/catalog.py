"""Catalogue endpoints: categories, suppliers, and stores."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser, require_roles
from app.core.rbac import Role
from app.db.session import get_db
from app.models.user import User
from app.schemas.catalog import (
    CategoryCreate,
    CategoryOut,
    CategoryUpdate,
    StoreCreate,
    StoreOut,
    StoreUpdate,
    SupplierCreate,
    SupplierOut,
    SupplierUpdate,
)
from app.schemas.common import Page
from app.services import catalog_service

ManagerUser = Annotated[User, Depends(require_roles(Role.OWNER, Role.ADMIN, Role.MANAGER))]

categories_router = APIRouter(prefix="/categories", tags=["categories"])
suppliers_router = APIRouter(prefix="/suppliers", tags=["suppliers"])
stores_router = APIRouter(prefix="/stores", tags=["stores"])


@categories_router.get("", response_model=Page[CategoryOut])
def list_categories(
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> Page[CategoryOut]:
    items, total = catalog_service.list_categories(
        db, org_id=user.org_id, limit=limit, offset=offset
    )
    return Page[CategoryOut](
        items=[CategoryOut.model_validate(i) for i in items],
        total=total,
        limit=limit,
        offset=offset,
    )


@categories_router.post("", response_model=CategoryOut, status_code=status.HTTP_201_CREATED)
def create_category(
    payload: CategoryCreate,
    user: ManagerUser,
    db: Annotated[Session, Depends(get_db)],
) -> CategoryOut:
    item = catalog_service.create_category(db, org_id=user.org_id, name=payload.name)
    return CategoryOut.model_validate(item)


@categories_router.get("/{category_id}", response_model=CategoryOut)
def get_category(
    category_id: uuid.UUID,
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> CategoryOut:
    item = catalog_service.get_category(db, org_id=user.org_id, category_id=category_id)
    return CategoryOut.model_validate(item)


@categories_router.patch("/{category_id}", response_model=CategoryOut)
def update_category(
    category_id: uuid.UUID,
    payload: CategoryUpdate,
    user: ManagerUser,
    db: Annotated[Session, Depends(get_db)],
) -> CategoryOut:
    item = catalog_service.update_category(
        db, org_id=user.org_id, category_id=category_id, name=payload.name
    )
    return CategoryOut.model_validate(item)


@categories_router.delete("/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_category(
    category_id: uuid.UUID,
    user: ManagerUser,
    db: Annotated[Session, Depends(get_db)],
) -> None:
    catalog_service.delete_category(db, org_id=user.org_id, category_id=category_id)


@suppliers_router.get("", response_model=Page[SupplierOut])
def list_suppliers(
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> Page[SupplierOut]:
    items, total = catalog_service.list_suppliers(
        db, org_id=user.org_id, limit=limit, offset=offset
    )
    return Page[SupplierOut](
        items=[SupplierOut.model_validate(i) for i in items],
        total=total,
        limit=limit,
        offset=offset,
    )


@suppliers_router.post("", response_model=SupplierOut, status_code=status.HTTP_201_CREATED)
def create_supplier(
    payload: SupplierCreate,
    user: ManagerUser,
    db: Annotated[Session, Depends(get_db)],
) -> SupplierOut:
    item = catalog_service.create_supplier(
        db,
        org_id=user.org_id,
        name=payload.name,
        contact_email=payload.contact_email,
        phone=payload.phone,
        lead_time_days=payload.lead_time_days,
    )
    return SupplierOut.model_validate(item)


@suppliers_router.get("/{supplier_id}", response_model=SupplierOut)
def get_supplier(
    supplier_id: uuid.UUID,
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> SupplierOut:
    item = catalog_service.get_supplier(db, org_id=user.org_id, supplier_id=supplier_id)
    return SupplierOut.model_validate(item)


@suppliers_router.patch("/{supplier_id}", response_model=SupplierOut)
def update_supplier(
    supplier_id: uuid.UUID,
    payload: SupplierUpdate,
    user: ManagerUser,
    db: Annotated[Session, Depends(get_db)],
) -> SupplierOut:
    item = catalog_service.update_supplier(
        db,
        org_id=user.org_id,
        supplier_id=supplier_id,
        name=payload.name,
        contact_email=payload.contact_email,
        phone=payload.phone,
        lead_time_days=payload.lead_time_days,
    )
    return SupplierOut.model_validate(item)


@suppliers_router.delete("/{supplier_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_supplier(
    supplier_id: uuid.UUID,
    user: ManagerUser,
    db: Annotated[Session, Depends(get_db)],
) -> None:
    catalog_service.delete_supplier(db, org_id=user.org_id, supplier_id=supplier_id)


@stores_router.get("", response_model=Page[StoreOut])
def list_stores(
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> Page[StoreOut]:
    items, total = catalog_service.list_stores(db, org_id=user.org_id, limit=limit, offset=offset)
    return Page[StoreOut](
        items=[StoreOut.model_validate(i) for i in items],
        total=total,
        limit=limit,
        offset=offset,
    )


@stores_router.post("", response_model=StoreOut, status_code=status.HTTP_201_CREATED)
def create_store(
    payload: StoreCreate,
    user: ManagerUser,
    db: Annotated[Session, Depends(get_db)],
) -> StoreOut:
    item = catalog_service.create_store(
        db, org_id=user.org_id, name=payload.name, location=payload.location
    )
    return StoreOut.model_validate(item)


@stores_router.get("/{store_id}", response_model=StoreOut)
def get_store(
    store_id: uuid.UUID,
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> StoreOut:
    item = catalog_service.get_store(db, org_id=user.org_id, store_id=store_id)
    return StoreOut.model_validate(item)


@stores_router.patch("/{store_id}", response_model=StoreOut)
def update_store(
    store_id: uuid.UUID,
    payload: StoreUpdate,
    user: ManagerUser,
    db: Annotated[Session, Depends(get_db)],
) -> StoreOut:
    item = catalog_service.update_store(
        db, org_id=user.org_id, store_id=store_id, name=payload.name, location=payload.location
    )
    return StoreOut.model_validate(item)


@stores_router.delete("/{store_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_store(
    store_id: uuid.UUID,
    user: ManagerUser,
    db: Annotated[Session, Depends(get_db)],
) -> None:
    catalog_service.delete_store(db, org_id=user.org_id, store_id=store_id)
