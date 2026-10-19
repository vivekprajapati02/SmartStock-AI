"""Tests for the reproducible synthetic seed generator (SQLite)."""

from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.inventory import SalesHistory
from app.models.organization import Organization
from app.models.product import Product
from seed.generate import generate_demo_data


def _sales_map(db: Session, slug: str) -> dict[tuple[str, str, object], str]:
    rows = db.execute(
        select(
            Product.sku, SalesHistory.store_id, SalesHistory.sale_date, SalesHistory.quantity
        )
        .join(Product, Product.id == SalesHistory.product_id)
        .join(Organization, Organization.id == SalesHistory.org_id)
        .where(Organization.slug == slug)
    ).all()
    return {
        (sku, str(store_id), sale_date): str(quantity)
        for sku, store_id, sale_date, quantity in rows
    }


def test_seed_creates_labelled_demo_org(db: Session):
    summary = generate_demo_data(
        db, slug="demo-org", num_products=3, num_stores=2, days=400, seed=11
    )
    assert summary["organization"]["is_demo"] is True
    org = db.execute(select(Organization).where(Organization.slug == "demo-org")).scalar_one()
    assert org.is_demo is True
    assert all(p.sku.startswith("DEMO-") for p in db.execute(select(Product)).scalars())


def test_seed_generates_at_least_twelve_months_of_sales(db: Session):
    generate_demo_data(db, slug="demo-range", num_products=2, num_stores=1, days=400, seed=5)
    span = db.execute(
        select(
            func.min(SalesHistory.sale_date),
            func.max(SalesHistory.sale_date),
            func.count(),
        )
    ).one()
    min_date, max_date, count = span
    assert (max_date - min_date).days >= 365
    assert count == 2 * 1 * 400


def test_seed_is_idempotent(db: Session):
    first = generate_demo_data(db, slug="demo-idem", num_products=3, num_stores=2, days=120, seed=3)
    count_after_first = db.execute(select(func.count()).select_from(SalesHistory)).scalar_one()

    second = generate_demo_data(
        db, slug="demo-idem", num_products=3, num_stores=2, days=120, seed=3
    )
    count_after_second = db.execute(select(func.count()).select_from(SalesHistory)).scalar_one()

    assert first["counts"]["sales_rows_created"] > 0
    assert second["counts"]["sales_rows_created"] == 0
    assert second["counts"]["inventory_rows_created"] == 0
    assert second["organization"]["created"] is False
    assert count_after_first == count_after_second


def test_seed_is_reproducible_across_orgs(db: Session):
    generate_demo_data(
        db, org_name="Repro A", slug="demo-repro-a", num_products=2, num_stores=2, days=30, seed=99
    )
    generate_demo_data(
        db, org_name="Repro B", slug="demo-repro-b", num_products=2, num_stores=2, days=30, seed=99
    )

    map_a = _sales_map(db, "demo-repro-a")
    map_b = _sales_map(db, "demo-repro-b")

    # Same seed + products + stores => identical quantity series (store ids differ).
    quantities_a = sorted(map_a.values())
    quantities_b = sorted(map_b.values())
    assert quantities_a == quantities_b
    assert len(quantities_a) == 2 * 2 * 30
