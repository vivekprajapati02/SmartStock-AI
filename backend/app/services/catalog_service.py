"""Catalogue CRUD: categories, suppliers, and stores."""

from __future__ import annotations

import uuid
from decimal import Decimal
from typing import TypeVar

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.errors import ConflictError, NotFoundError
from app.db.session import set_org_context
from app.models.catalog import Category, Store, Supplier
from app.models.inventory import Inventory
from app.models.product import Product

T = TypeVar("T")


def _ensure_org(db: Session, org_id: uuid.UUID) -> None:
    set_org_context(db, org_id)


def _count(db: Session, model, org_id: uuid.UUID) -> int:
    return int(
        db.execute(
            select(func.count()).select_from(model).where(model.org_id == org_id)
        ).scalar_one()
    )


def _commit_or_conflict(db: Session, message: str) -> None:
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise ConflictError(message) from exc


# --- Categories -------------------------------------------------------------


def list_categories(
    db: Session, *, org_id: uuid.UUID, limit: int, offset: int
) -> tuple[list[Category], int]:
    _ensure_org(db, org_id)
    total = _count(db, Category, org_id)
    items = (
        db.execute(
            select(Category)
            .where(Category.org_id == org_id)
            .order_by(Category.name)
            .limit(limit)
            .offset(offset)
        )
        .scalars()
        .all()
    )
    return list(items), total


def get_category(db: Session, *, org_id: uuid.UUID, category_id: uuid.UUID) -> Category:
    _ensure_org(db, org_id)
    category = db.get(Category, category_id)
    if category is None or category.org_id != org_id:
        raise NotFoundError("Category not found.")
    return category


def create_category(db: Session, *, org_id: uuid.UUID, name: str) -> Category:
    _ensure_org(db, org_id)
    category = Category(id=uuid.uuid4(), org_id=org_id, name=name.strip())
    db.add(category)
    _commit_or_conflict(db, "A category with this name already exists.")
    db.refresh(category)
    return category


def update_category(
    db: Session, *, org_id: uuid.UUID, category_id: uuid.UUID, name: str
) -> Category:
    category = get_category(db, org_id=org_id, category_id=category_id)
    category.name = name.strip()
    _commit_or_conflict(db, "A category with this name already exists.")
    db.refresh(category)
    return category


def delete_category(db: Session, *, org_id: uuid.UUID, category_id: uuid.UUID) -> None:
    category = get_category(db, org_id=org_id, category_id=category_id)
    db.delete(category)
    db.commit()


# --- Suppliers --------------------------------------------------------------


def list_suppliers(
    db: Session, *, org_id: uuid.UUID, limit: int, offset: int
) -> tuple[list[Supplier], int]:
    _ensure_org(db, org_id)
    total = _count(db, Supplier, org_id)
    items = (
        db.execute(
            select(Supplier)
            .where(Supplier.org_id == org_id)
            .order_by(Supplier.name)
            .limit(limit)
            .offset(offset)
        )
        .scalars()
        .all()
    )
    return list(items), total


def get_supplier(db: Session, *, org_id: uuid.UUID, supplier_id: uuid.UUID) -> Supplier:
    _ensure_org(db, org_id)
    supplier = db.get(Supplier, supplier_id)
    if supplier is None or supplier.org_id != org_id:
        raise NotFoundError("Supplier not found.")
    return supplier


def create_supplier(
    db: Session,
    *,
    org_id: uuid.UUID,
    name: str,
    contact_email: str | None,
    phone: str | None,
    lead_time_days: int,
) -> Supplier:
    _ensure_org(db, org_id)
    supplier = Supplier(
        id=uuid.uuid4(),
        org_id=org_id,
        name=name.strip(),
        contact_email=contact_email,
        phone=phone,
        lead_time_days=lead_time_days,
    )
    db.add(supplier)
    _commit_or_conflict(db, "A supplier with this name already exists.")
    db.refresh(supplier)
    return supplier


def update_supplier(
    db: Session,
    *,
    org_id: uuid.UUID,
    supplier_id: uuid.UUID,
    name: str | None,
    contact_email: str | None,
    phone: str | None,
    lead_time_days: int | None,
) -> Supplier:
    supplier = get_supplier(db, org_id=org_id, supplier_id=supplier_id)
    if name is not None:
        supplier.name = name.strip()
    if contact_email is not None:
        supplier.contact_email = contact_email
    if phone is not None:
        supplier.phone = phone
    if lead_time_days is not None:
        supplier.lead_time_days = lead_time_days
    _commit_or_conflict(db, "A supplier with this name already exists.")
    db.refresh(supplier)
    return supplier


def delete_supplier(db: Session, *, org_id: uuid.UUID, supplier_id: uuid.UUID) -> None:
    supplier = get_supplier(db, org_id=org_id, supplier_id=supplier_id)
    db.delete(supplier)
    db.commit()


# --- Stores -----------------------------------------------------------------


def list_stores(
    db: Session, *, org_id: uuid.UUID, limit: int, offset: int
) -> tuple[list[Store], int]:
    _ensure_org(db, org_id)
    total = _count(db, Store, org_id)
    items = (
        db.execute(
            select(Store)
            .where(Store.org_id == org_id)
            .order_by(Store.name)
            .limit(limit)
            .offset(offset)
        )
        .scalars()
        .all()
    )
    return list(items), total


def get_store(db: Session, *, org_id: uuid.UUID, store_id: uuid.UUID) -> Store:
    _ensure_org(db, org_id)
    store = db.get(Store, store_id)
    if store is None or store.org_id != org_id:
        raise NotFoundError("Store not found.")
    return store


def create_store(db: Session, *, org_id: uuid.UUID, name: str, location: str | None) -> Store:
    _ensure_org(db, org_id)
    store = Store(id=uuid.uuid4(), org_id=org_id, name=name.strip(), location=location)
    db.add(store)
    # Flush the store before the inventory rows referencing it (see
    # product_service.create_product for why the order matters).
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        raise ConflictError("A store with this name already exists.") from exc
    with db.no_autoflush:
        products = db.execute(select(Product).where(Product.org_id == org_id)).scalars().all()
        for product in products:
            db.add(
                Inventory(
                    id=uuid.uuid4(),
                    org_id=org_id,
                    product_id=product.id,
                    store_id=store.id,
                    quantity_on_hand=Decimal("0"),
                )
            )
    _commit_or_conflict(db, "A store with this name already exists.")
    db.refresh(store)
    return store


def update_store(
    db: Session,
    *,
    org_id: uuid.UUID,
    store_id: uuid.UUID,
    name: str | None,
    location: str | None,
) -> Store:
    store = get_store(db, org_id=org_id, store_id=store_id)
    if name is not None:
        store.name = name.strip()
    if location is not None:
        store.location = location
    _commit_or_conflict(db, "A store with this name already exists.")
    db.refresh(store)
    return store


def delete_store(db: Session, *, org_id: uuid.UUID, store_id: uuid.UUID) -> None:
    store = get_store(db, org_id=org_id, store_id=store_id)
    db.delete(store)
    db.commit()
