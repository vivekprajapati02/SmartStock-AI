"""Catalogue reference data: categories, suppliers, and stores."""

from __future__ import annotations

from sqlalchemy import Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, OrgScopedMixin, TimestampMixin, UUIDPrimaryKeyMixin


class Category(Base, UUIDPrimaryKeyMixin, OrgScopedMixin, TimestampMixin):
    __tablename__ = "categories"
    __table_args__ = (UniqueConstraint("org_id", "name", name="uq_categories_org_name"),)

    name: Mapped[str] = mapped_column(String(120), nullable=False)


class Supplier(Base, UUIDPrimaryKeyMixin, OrgScopedMixin, TimestampMixin):
    __tablename__ = "suppliers"
    __table_args__ = (UniqueConstraint("org_id", "name", name="uq_suppliers_org_name"),)

    name: Mapped[str] = mapped_column(String(200), nullable=False)
    contact_email: Mapped[str | None] = mapped_column(String(255), nullable=True)
    phone: Mapped[str | None] = mapped_column(String(40), nullable=True)
    lead_time_days: Mapped[int] = mapped_column(
        Integer, nullable=False, default=7, server_default="7"
    )


class Store(Base, UUIDPrimaryKeyMixin, OrgScopedMixin, TimestampMixin):
    __tablename__ = "stores"
    __table_args__ = (UniqueConstraint("org_id", "name", name="uq_stores_org_name"),)

    name: Mapped[str] = mapped_column(String(200), nullable=False)
    location: Mapped[str | None] = mapped_column(String(255), nullable=True)
