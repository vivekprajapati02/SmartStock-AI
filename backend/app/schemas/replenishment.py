"""Replenishment recommendation schemas. Every value is computed from stored
inventory, sales history, forecasts and open purchase orders."""

from __future__ import annotations

import uuid
from typing import Literal

from pydantic import Field

from app.schemas.common import APIModel


class ReplenishmentItem(APIModel):
    inventory_id: uuid.UUID
    product_id: uuid.UUID
    store_id: uuid.UUID
    sku: str
    product_name: str
    store_name: str
    supplier_id: uuid.UUID | None = None
    supplier_name: str | None = None
    on_hand: float
    on_order: float
    inventory_position: float
    lead_time_days: int
    review_days: int
    avg_daily_demand: float
    demand_std: float
    demand_source: Literal["forecast", "history", "none"]
    forecast_model: str | None = None
    lead_time_demand: float
    safety_stock: float
    reorder_point: float
    target_stock: float
    recommended_qty: float
    days_of_cover: float | None = None
    needs_reorder: bool
    current_reorder_point: float
    current_safety_stock: float


class ReplenishmentList(APIModel):
    items: list[ReplenishmentItem]
    total: int
    limit: int
    offset: int
    service_level: float
    z_score: float
    review_days: int
    history_days: int
    history_end: str | None = None


class ApplyRequest(APIModel):
    """Write computed reorder point and safety stock into inventory settings."""

    inventory_ids: list[uuid.UUID] | None = Field(
        default=None, description="Rows to update; all rows in scope when omitted."
    )
    store_id: uuid.UUID | None = None
    service_level: float = Field(default=0.95, ge=0.5, le=0.999)
    review_days: int = Field(default=7, ge=1, le=90)


class ApplyResult(APIModel):
    updated: int
