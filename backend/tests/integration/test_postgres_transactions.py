"""PostgreSQL transaction and rollback integration tests."""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy import Engine, insert, select, text
from sqlalchemy.exc import DBAPIError, IntegrityError

from app.models.catalog import Store
from app.models.inventory import Inventory
from app.models.organization import Organization
from app.models.product import Product

pytestmark = pytest.mark.postgres


def _seed_context(connection, org_id: uuid.UUID) -> None:
    connection.execute(
        text("SELECT set_config('app.current_org', :org, true)"), {"org": str(org_id)}
    )


def test_failed_transaction_rolls_back_completely(pg_engine: Engine):
    org_id = uuid.uuid4()
    slug = f"tx-rollback-{uuid.uuid4().hex[:8]}"
    product_id = uuid.uuid4()
    store_id = uuid.uuid4()
    inventory_id = uuid.uuid4()

    with pg_engine.connect() as connection:
        transaction = connection.begin()
        connection.execute(
            insert(Organization.__table__).values(
                id=org_id, name="Rollback Org", slug=slug, is_demo=True
            )
        )
        _seed_context(connection, org_id)
        connection.execute(
            insert(Product.__table__).values(
                id=product_id, org_id=org_id, sku="TX-1", name="Widget", unit="unit",
                unit_cost=1, unit_price=2, is_active=True,
            )
        )
        connection.execute(
            insert(Store.__table__).values(id=store_id, org_id=org_id, name="Tx Store")
        )
        connection.execute(
            insert(Inventory.__table__).values(
                id=inventory_id, org_id=org_id, product_id=product_id, store_id=store_id,
                quantity_on_hand=50, reorder_point=0, safety_stock=0, lead_time_days=7,
            )
        )
        # Sanity: the rows are visible inside the transaction.
        assert connection.execute(
            select(Inventory.quantity_on_hand).where(Inventory.id == inventory_id)
        ).scalar_one() == 50

        # Force a failure (duplicate primary key) and roll the whole thing back.
        with pytest.raises(IntegrityError):
            connection.execute(
                insert(Inventory.__table__).values(
                    id=inventory_id, org_id=org_id, product_id=product_id, store_id=store_id,
                    quantity_on_hand=99, reorder_point=0, safety_stock=0, lead_time_days=7,
                )
            )
        transaction.rollback()

    # A fresh transaction must see none of the aborted writes.
    with pg_engine.connect() as connection:
        transaction = connection.begin()
        assert connection.execute(
            text("SELECT count(*) FROM organizations WHERE slug = :slug"), {"slug": slug}
        ).scalar() == 0
        _seed_context(connection, org_id)
        assert connection.execute(
            select(Inventory.id).where(Inventory.id == inventory_id)
        ).scalar_one_or_none() is None
        assert connection.execute(
            select(Product.id).where(Product.id == product_id)
        ).scalar_one_or_none() is None
        transaction.rollback()


def test_inventory_update_is_atomic(pg_engine: Engine):
    """A multi-statement inventory update either fully applies or not at all."""
    unique = uuid.uuid4().hex[:8]
    org_id = uuid.uuid4()
    slug = f"tx-atomic-{unique}"
    product_id = uuid.uuid4()
    store_id = uuid.uuid4()

    # Commit an initial state.
    with pg_engine.begin() as connection:
        connection.execute(
            insert(Organization.__table__).values(
                id=org_id, name=f"Atomic Org {unique}", slug=slug, is_demo=True
            )
        )
        _seed_context(connection, org_id)
        connection.execute(
            insert(Product.__table__).values(
                id=product_id, org_id=org_id, sku="AT-1", name="Widget", unit="unit",
                unit_cost=1, unit_price=2, is_active=True,
            )
        )
        connection.execute(
            insert(Store.__table__).values(id=store_id, org_id=org_id, name="Atomic Store")
        )
        connection.execute(
            insert(Inventory.__table__).values(
                id=uuid.uuid4(), org_id=org_id, product_id=product_id, store_id=store_id,
                quantity_on_hand=10, reorder_point=0, safety_stock=0, lead_time_days=7,
            )
        )

    # Attempt an update that fails halfway; roll back and verify original value.
    with pg_engine.connect() as connection:
        transaction = connection.begin()
        _seed_context(connection, org_id)
        connection.execute(
            text(
                "UPDATE inventory SET quantity_on_hand = 999 "
                "WHERE org_id = :org AND product_id = :product"
            ),
            {"org": str(org_id), "product": str(product_id)},
        )
        with pytest.raises(DBAPIError):
            connection.execute(
                text("SELECT 1/0")  # simulate an error mid-transaction
            )
        transaction.rollback()

    with pg_engine.connect() as connection:
        transaction = connection.begin()
        _seed_context(connection, org_id)
        on_hand = connection.execute(
            select(Inventory.quantity_on_hand).where(Inventory.product_id == product_id)
        ).scalar_one()
        assert float(on_hand) == 10
        transaction.rollback()
