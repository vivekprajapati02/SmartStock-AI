"""Reproducible synthetic demo data generator.

Design goals:
- **Reproducible**: all randomness derives from a single ``--seed`` and stable
  hash-based sub-seeds, so the same arguments always produce the same data.
- **Idempotent**: every entity is looked up by its natural key before creation,
  and sales rows are keyed by ``(org, product, store, date)``. Re-running adds
  nothing new and never deletes data.
- **Clearly labelled**: the organisation is created with ``is_demo=True`` and all
  products use a ``DEMO-`` SKU prefix, so synthetic demo data is unmistakable.

Usage::

    python -m seed.generate --slug acme-demo --days 400
"""

from __future__ import annotations

import argparse
import hashlib
import random
import uuid
from datetime import date, timedelta
from decimal import Decimal

from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import get_settings
from app.core.logging import get_logger
from app.core.rbac import Role
from app.core.security import hash_password
from app.db.session import set_org_context
from app.models.catalog import Category, Store, Supplier
from app.models.enums import MovementType
from app.models.inventory import Inventory, SalesHistory, StockMovement
from app.models.organization import Organization
from app.models.product import Product
from app.models.user import User

logger = get_logger(__name__)

CATEGORY_NAMES = ["Beverages", "Snacks", "Household", "Personal Care", "Dairy"]
SUPPLIER_NAMES = ["Northwind Supply", "Global Foods", "Daily Distributors", "Prime Goods"]
PRODUCT_ADJECTIVES = [
    "Classic", "Premium", "Organic", "Everyday", "Deluxe", "Value",
    "Fresh", "Golden", "Rustic", "Supreme",
]
PRODUCT_NOUNS = [
    "Coffee", "Tea", "Chocolate", "Cereal", "Juice", "Water", "Soap",
    "Shampoo", "Chips", "Cookies", "Milk", "Yogurt",
]


def _stable_seed(*parts: object) -> int:
    digest = hashlib.sha256("|".join(str(p) for p in parts).encode("utf-8")).hexdigest()
    return int(digest[:16], 16)


def _find_or_create(db: Session, model, defaults: dict | None = None, **lookup):
    instance = db.execute(select(model).filter_by(**lookup)).scalar_one_or_none()
    if instance is not None:
        return instance, False
    instance = model(**lookup, **(defaults or {}))
    db.add(instance)
    db.flush()
    return instance, True


def _daily_quantity(
    rng: random.Random, day_index: int, weekday: int, base: float, trend: float
) -> int:
    """A single day's demand with trend, weekly seasonality, promo, and noise."""
    level = base * (1.0 + trend * day_index)
    weekly = 1.15 if weekday >= 5 else 1.0  # busier on weekends
    promo = 1.6 if rng.random() < 0.02 else 1.0
    noise = rng.gauss(1.0, 0.18)
    value = level * weekly * promo * noise
    return max(0, int(round(value)))


def generate_demo_data(
    db: Session,
    *,
    org_name: str = "Synthetic Demo Co",
    slug: str = "synthetic-demo",
    owner_email: str = "owner@synthetic-demo.com",
    owner_password: str = "demo-password-123",
    owner_name: str = "Demo Owner",
    days: int = 400,
    num_products: int = 15,
    num_stores: int = 2,
    seed: int = 42,
) -> dict[str, object]:
    """Create (or top up) a clearly-labelled synthetic demo organisation."""
    rng = random.Random(seed)

    org, org_created = _find_or_create(
        db,
        Organization,
        defaults={"is_demo": True},
        name=org_name,
        slug=slug,
    )
    if not org.is_demo:
        org.is_demo = True
    set_org_context(db, org.id)

    owner, user_created = _find_or_create(
        db,
        User,
        defaults={
            "hashed_password": hash_password(owner_password),
            "full_name": owner_name,
            "role": Role.OWNER,
            "is_active": True,
        },
        org_id=org.id,
        email=owner_email.strip().lower(),
    )

    categories = []
    for name in CATEGORY_NAMES:
        category, _ = _find_or_create(db, Category, org_id=org.id, name=name)
        categories.append(category)

    suppliers = []
    for i, name in enumerate(SUPPLIER_NAMES):
        supplier, _ = _find_or_create(
            db,
            Supplier,
            defaults={
                "contact_email": f"orders{i + 1}@{slug}.com",
                "phone": f"+1-555-01{i:02d}",
                "lead_time_days": rng.choice([3, 5, 7, 10, 14]),
            },
            org_id=org.id,
            name=name,
        )
        suppliers.append(supplier)

    stores = []
    for i in range(num_stores):
        store, _ = _find_or_create(
            db,
            Store,
            defaults={"location": f"Region {i + 1}"},
            org_id=org.id,
            name=f"Store {i + 1}",
        )
        stores.append(store)

    db.flush()

    products: list[Product] = []
    product_lead_time: dict[uuid.UUID, int] = {}
    for i in range(num_products):
        sku = f"DEMO-{i + 1:04d}"
        adjective = PRODUCT_ADJECTIVES[i % len(PRODUCT_ADJECTIVES)]
        noun = PRODUCT_NOUNS[i % len(PRODUCT_NOUNS)]
        name = f"{adjective} {noun}"
        supplier = suppliers[i % len(suppliers)]
        product, _ = _find_or_create(
            db,
            Product,
            defaults={
                "name": name,
                "category_id": categories[i % len(categories)].id,
                "supplier_id": supplier.id,
                "unit": "unit",
                "unit_cost": Decimal(f"{round(rng.uniform(1.5, 18.0), 2)}"),
                "unit_price": Decimal(f"{round(rng.uniform(3.0, 30.0), 2)}"),
                "is_active": True,
            },
            org_id=org.id,
            sku=sku,
        )
        products.append(product)
        product_lead_time[product.id] = supplier.lead_time_days

    db.flush()

    today = date.today()
    start_date = today - timedelta(days=days - 1)

    created = {"inventory": 0, "stock_movements": 0, "sales_history": 0}

    for product in products:
        for store in stores:
            pair_seed = _stable_seed(seed, product.sku, store.name)
            pair_rng = random.Random(pair_seed)
            base_demand = pair_rng.uniform(6.0, 40.0)
            trend = pair_rng.uniform(-0.00020, 0.00060)

            inventory, inv_created = _find_or_create(
                db,
                Inventory,
                defaults={
                    "quantity_on_hand": Decimal(int(base_demand * 10)),
                    "reorder_point": Decimal(int(base_demand * 4)),
                    "safety_stock": Decimal(int(base_demand * 2)),
                    "lead_time_days": product_lead_time[product.id],
                },
                org_id=org.id,
                product_id=product.id,
                store_id=store.id,
            )
            if inv_created:
                created["inventory"] += 1
                db.add(
                    StockMovement(
                        id=uuid.uuid4(),
                        org_id=org.id,
                        product_id=product.id,
                        store_id=store.id,
                        movement_type=MovementType.IN,
                        quantity=inventory.quantity_on_hand,
                        reference="DEMO-SEED",
                        note="Synthetic opening balance",
                    )
                )
                created["stock_movements"] += 1

            # Determine which dates already exist to keep the seed idempotent.
            existing_dates = set(
                db.execute(
                    select(SalesHistory.sale_date).where(
                        SalesHistory.org_id == org.id,
                        SalesHistory.product_id == product.id,
                        SalesHistory.store_id == store.id,
                        SalesHistory.sale_date >= start_date,
                        SalesHistory.sale_date <= today,
                    )
                )
                .scalars()
                .all()
            )

            new_rows = []
            for day_index in range(days):
                sale_day = start_date + timedelta(days=day_index)
                if sale_day in existing_dates:
                    continue
                qty = _daily_quantity(pair_rng, day_index, sale_day.weekday(), base_demand, trend)
                new_rows.append(
                    {
                        "id": uuid.uuid4(),
                        "org_id": org.id,
                        "product_id": product.id,
                        "store_id": store.id,
                        "sale_date": sale_day,
                        "quantity": Decimal(qty),
                    }
                )
            if new_rows:
                db.execute(SalesHistory.__table__.insert(), new_rows)
                created["sales_history"] += len(new_rows)

    db.commit()

    summary = {
        "organization": {"slug": org.slug, "name": org.name, "is_demo": org.is_demo,
                         "created": org_created},
        "owner_email": owner.email,
        "owner_created": user_created,
        "counts": {
            "categories": len(categories),
            "suppliers": len(suppliers),
            "stores": len(stores),
            "products": len(products),
            "sales_rows_created": created["sales_history"],
            "inventory_rows_created": created["inventory"],
            "movements_created": created["stock_movements"],
        },
        "date_range": {"start": start_date.isoformat(), "end": today.isoformat(), "days": days},
    }
    logger.info(
        "Demo data ready for %s (%s new sales rows)", org.slug, created["sales_history"]
    )
    return summary


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate SmartStock AI synthetic demo data.")
    parser.add_argument("--org-name", default="Synthetic Demo Co")
    parser.add_argument("--slug", default="synthetic-demo")
    parser.add_argument("--email", default="owner@synthetic-demo.com")
    parser.add_argument("--password", default="demo-password-123")
    parser.add_argument("--owner-name", default="Demo Owner")
    parser.add_argument("--days", type=int, default=400)
    parser.add_argument("--products", type=int, default=15)
    parser.add_argument("--stores", type=int, default=2)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--database-url", default=None)
    return parser


def main(argv: list[str] | None = None) -> int:
    import json

    args = _build_parser().parse_args(argv)
    url = args.database_url or get_settings().database_url
    engine = create_engine(url)
    factory = sessionmaker(bind=engine, expire_on_commit=False, future=True)
    with factory() as db:
        summary = generate_demo_data(
            db,
            org_name=args.org_name,
            slug=args.slug,
            owner_email=args.email,
            owner_password=args.password,
            owner_name=args.owner_name,
            days=args.days,
            num_products=args.products,
            num_stores=args.stores,
            seed=args.seed,
        )
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
