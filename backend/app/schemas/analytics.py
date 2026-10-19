"""Dashboard analytics schemas. All numbers are computed from stored data."""

from __future__ import annotations

from datetime import date
from decimal import Decimal

from app.schemas.common import APIModel


class DemandPoint(APIModel):
    sale_date: date
    quantity: Decimal


class DashboardOut(APIModel):
    inventory_value: Decimal
    sku_count: int
    store_count: int
    low_stock_count: int
    stockout_count: int
    pending_order_count: int
    demand_trend: list[DemandPoint]
    is_demo: bool = False
