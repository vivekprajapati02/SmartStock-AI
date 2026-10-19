"""Purchase orders and their line items (partial receipts supported)."""

from __future__ import annotations

import uuid
from datetime import date
from decimal import Decimal

from sqlalchemy import Date, ForeignKey, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, OrgScopedMixin, TimestampMixin, UUIDPrimaryKeyMixin
from app.models.enums import PurchaseOrderStatus, enum_column


class PurchaseOrder(Base, UUIDPrimaryKeyMixin, OrgScopedMixin, TimestampMixin):
    __tablename__ = "purchase_orders"

    supplier_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("suppliers.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    store_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("stores.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    status: Mapped[PurchaseOrderStatus] = mapped_column(
        enum_column(PurchaseOrderStatus, "purchase_order_status"),
        nullable=False,
        default=PurchaseOrderStatus.DRAFT,
        index=True,
    )
    reference: Mapped[str | None] = mapped_column(String(120), nullable=True)
    created_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    approved_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    expected_date: Mapped[date | None] = mapped_column(Date, nullable=True)

    items: Mapped[list[PurchaseOrderItem]] = relationship(
        "PurchaseOrderItem", back_populates="purchase_order", cascade="all, delete-orphan"
    )


class PurchaseOrderItem(Base, UUIDPrimaryKeyMixin, OrgScopedMixin, TimestampMixin):
    __tablename__ = "purchase_order_items"

    purchase_order_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("purchase_orders.id", ondelete="CASCADE"), nullable=False, index=True
    )
    product_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    quantity_ordered: Mapped[Decimal] = mapped_column(Numeric(14, 3), nullable=False)
    quantity_received: Mapped[Decimal] = mapped_column(
        Numeric(14, 3), nullable=False, default=Decimal("0"), server_default="0"
    )

    purchase_order: Mapped[PurchaseOrder] = relationship(
        "PurchaseOrder", back_populates="items"
    )
