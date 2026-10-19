"""ORM model package.

Importing this package registers every table on ``Base.metadata`` so Alembic
autogenerate and ``create_all`` see the full schema.
"""

from __future__ import annotations

from app.db.base import Base
from app.models.alert import Alert
from app.models.catalog import Category, Store, Supplier
from app.models.enums import (
    AlertSeverity,
    AlertStatus,
    AlertType,
    ImportStatus,
    MovementType,
    PurchaseOrderStatus,
)
from app.models.forecasting import Forecast, ModelRun
from app.models.imports import ImportBatch
from app.models.inventory import Inventory, SalesHistory, StockMovement
from app.models.organization import Organization
from app.models.product import Product
from app.models.purchasing import PurchaseOrder, PurchaseOrderItem
from app.models.user import User

__all__ = [
    "Base",
    "Organization",
    "User",
    "Category",
    "Supplier",
    "Store",
    "Product",
    "Inventory",
    "StockMovement",
    "SalesHistory",
    "ModelRun",
    "Forecast",
    "Alert",
    "PurchaseOrder",
    "PurchaseOrderItem",
    "ImportBatch",
    "MovementType",
    "PurchaseOrderStatus",
    "AlertType",
    "AlertSeverity",
    "AlertStatus",
    "ImportStatus",
]
