"""Inventory state, the stock movement ledger, and sales history."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import Date, DateTime, ForeignKey, Integer, Numeric, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, OrgScopedMixin, TimestampMixin, UUIDPrimaryKeyMixin
from app.models.enums import MovementType, enum_column


class Inventory(Base, UUIDPrimaryKeyMixin, OrgScopedMixin, TimestampMixin):
    """Current stock level per product/store. Updated only via services."""

    __tablename__ = "inventory"
    __table_args__ = (
        UniqueConstraint("org_id", "product_id", "store_id", name="uq_inventory_org_product_store"),
    )

    product_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("products.id", ondelete="CASCADE"), nullable=False, index=True
    )
    store_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("stores.id", ondelete="CASCADE"), nullable=False, index=True
    )
    quantity_on_hand: Mapped[Decimal] = mapped_column(
        Numeric(14, 3), nullable=False, default=Decimal("0"), server_default="0"
    )
    reorder_point: Mapped[Decimal] = mapped_column(
        Numeric(14, 3), nullable=False, default=Decimal("0"), server_default="0"
    )
    safety_stock: Mapped[Decimal] = mapped_column(
        Numeric(14, 3), nullable=False, default=Decimal("0"), server_default="0"
    )
    lead_time_days: Mapped[int] = mapped_column(
        Integer, nullable=False, default=7, server_default="7"
    )


class StockMovement(Base, UUIDPrimaryKeyMixin, OrgScopedMixin, TimestampMixin):
    """Immutable ledger of stock changes; the source of truth for inventory."""

    __tablename__ = "stock_movements"

    product_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("products.id", ondelete="CASCADE"), nullable=False, index=True
    )
    store_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("stores.id", ondelete="CASCADE"), nullable=False, index=True
    )
    movement_type: Mapped[MovementType] = mapped_column(
        enum_column(MovementType, "movement_type"), nullable=False
    )
    quantity: Mapped[Decimal] = mapped_column(Numeric(14, 3), nullable=False)
    reference: Mapped[str | None] = mapped_column(String(120), nullable=True)
    note: Mapped[str | None] = mapped_column(String(500), nullable=True)
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


class SalesHistory(Base, UUIDPrimaryKeyMixin, OrgScopedMixin, TimestampMixin):
    """Daily sold quantity per product/store; the forecasting input."""

    __tablename__ = "sales_history"
    __table_args__ = (
        UniqueConstraint(
            "org_id", "product_id", "store_id", "sale_date",
            name="uq_sales_history_org_product_store_date",
        ),
    )

    product_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("products.id", ondelete="CASCADE"), nullable=False, index=True
    )
    store_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("stores.id", ondelete="CASCADE"), nullable=False, index=True
    )
    sale_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    quantity: Mapped[Decimal] = mapped_column(Numeric(14, 3), nullable=False)
