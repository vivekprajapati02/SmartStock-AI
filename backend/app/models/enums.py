"""Shared enumerations used by ORM models and API schemas."""

from __future__ import annotations

from enum import StrEnum

from sqlalchemy import Enum as SAEnum


class MovementType(StrEnum):
    IN = "in"
    OUT = "out"
    ADJUST = "adjust"


class PurchaseOrderStatus(StrEnum):
    DRAFT = "draft"
    PENDING = "pending"
    APPROVED = "approved"
    PARTIAL = "partial"
    RECEIVED = "received"
    CANCELLED = "cancelled"


class AlertType(StrEnum):
    LOW_STOCK = "low_stock"
    STOCKOUT_RISK = "stockout_risk"
    OVERSTOCK = "overstock"
    SLOW_MOVING = "slow_moving"


class AlertSeverity(StrEnum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


class AlertStatus(StrEnum):
    OPEN = "open"
    ACKNOWLEDGED = "acknowledged"
    RESOLVED = "resolved"
    DISMISSED = "dismissed"


class ImportStatus(StrEnum):
    PENDING = "pending"
    COMPLETED = "completed"
    PARTIAL = "partial"
    FAILED = "failed"


def enum_column(enum_cls: type[StrEnum], name: str, length: int = 32) -> SAEnum:
    """A portable string-backed enum column (no native PostgreSQL enum type).

    ``values_callable`` makes the database store the member *value* (e.g.
    ``"owner"``) rather than the member name (``"OWNER"``), keeping stored values
    consistent with the API representation.
    """
    return SAEnum(
        enum_cls,
        name=name,
        native_enum=False,
        validate_strings=True,
        length=length,
        values_callable=lambda cls: [member.value for member in cls],
    )
