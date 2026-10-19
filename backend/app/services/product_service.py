"""Product CRUD (org-scoped)."""

from __future__ import annotations

import uuid
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.errors import ConflictError, NotFoundError
from app.db.session import set_org_context
from app.models.catalog import Category, Store, Supplier
from app.models.inventory import Inventory
from app.models.product import Product


def _ensure_org(db: Session, org_id: uuid.UUID) -> None:
    set_org_context(db, org_id)


def _require_optional_fk(
    db: Session, *, org_id: uuid.UUID, category_id: uuid.UUID | None, supplier_id: uuid.UUID | None
) -> None:
    if category_id is not None:
        category = db.get(Category, category_id)
        if category is None or category.org_id != org_id:
            raise NotFoundError("Category not found.")
    if supplier_id is not None:
        supplier = db.get(Supplier, supplier_id)
        if supplier is None or supplier.org_id != org_id:
            raise NotFoundError("Supplier not found.")


def list_products(
    db: Session,
    *,
    org_id: uuid.UUID,
    limit: int,
    offset: int,
    search: str | None = None,
    is_active: bool | None = None,
) -> tuple[list[Product], int]:
    _ensure_org(db, org_id)
    query = select(Product).where(Product.org_id == org_id)
    count_query = select(func.count()).select_from(Product).where(Product.org_id == org_id)
    if is_active is not None:
        query = query.where(Product.is_active == is_active)
        count_query = count_query.where(Product.is_active == is_active)
    if search:
        pattern = f"%{search.strip().lower()}%"
        query = query.where(
            func.lower(Product.name).like(pattern) | func.lower(Product.sku).like(pattern)
        )
        count_query = count_query.where(
            func.lower(Product.name).like(pattern) | func.lower(Product.sku).like(pattern)
        )
    total = int(db.execute(count_query).scalar_one())
    items = (
        db.execute(query.order_by(Product.sku).limit(limit).offset(offset)).scalars().all()
    )
    return list(items), total


def get_product(db: Session, *, org_id: uuid.UUID, product_id: uuid.UUID) -> Product:
    _ensure_org(db, org_id)
    product = db.get(Product, product_id)
    if product is None or product.org_id != org_id:
        raise NotFoundError("Product not found.")
    return product


def create_product(
    db: Session,
    *,
    org_id: uuid.UUID,
    sku: str,
    name: str,
    category_id: uuid.UUID | None,
    supplier_id: uuid.UUID | None,
    unit: str,
    unit_cost: Decimal,
    unit_price: Decimal,
    is_active: bool,
) -> Product:
    _ensure_org(db, org_id)
    _require_optional_fk(db, org_id=org_id, category_id=category_id, supplier_id=supplier_id)
    product = Product(
        id=uuid.uuid4(),
        org_id=org_id,
        sku=sku.strip(),
        name=name.strip(),
        category_id=category_id,
        supplier_id=supplier_id,
        unit=unit,
        unit_cost=unit_cost,
        unit_price=unit_price,
        is_active=is_active,
    )
    db.add(product)
    # Insert the product before the inventory rows that reference it: with no
    # ORM relationship between them, the flush order is otherwise undefined and
    # PostgreSQL (which enforces foreign keys) can reject the inventory insert.
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        raise ConflictError("A product with this SKU already exists.") from exc
    with db.no_autoflush:
        stores = db.execute(select(Store).where(Store.org_id == org_id)).scalars().all()
        for store in stores:
            db.add(
                Inventory(
                    id=uuid.uuid4(),
                    org_id=org_id,
                    product_id=product.id,
                    store_id=store.id,
                    quantity_on_hand=Decimal("0"),
                )
            )
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise ConflictError("A product with this SKU already exists.") from exc
    db.refresh(product)
    return product


def update_product(
    db: Session,
    *,
    org_id: uuid.UUID,
    product_id: uuid.UUID,
    sku: str | None,
    name: str | None,
    category_id: uuid.UUID | None,
    supplier_id: uuid.UUID | None,
    unit: str | None,
    unit_cost: Decimal | None,
    unit_price: Decimal | None,
    is_active: bool | None,
) -> Product:
    product = get_product(db, org_id=org_id, product_id=product_id)
    _require_optional_fk(db, org_id=org_id, category_id=category_id, supplier_id=supplier_id)
    if sku is not None:
        product.sku = sku.strip()
    if name is not None:
        product.name = name.strip()
    if category_id is not None:
        product.category_id = category_id
    if supplier_id is not None:
        product.supplier_id = supplier_id
    if unit is not None:
        product.unit = unit
    if unit_cost is not None:
        product.unit_cost = unit_cost
    if unit_price is not None:
        product.unit_price = unit_price
    if is_active is not None:
        product.is_active = is_active
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise ConflictError("A product with this SKU already exists.") from exc
    db.refresh(product)
    return product
