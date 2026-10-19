"""Inventory and stock-movement schemas."""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import Field, model_validator

from app.models.enums import MovementType
from app.schemas.common import APIModel


class InventoryOut(APIModel):
    id: uuid.UUID
    org_id: uuid.UUID
    product_id: uuid.UUID
    store_id: uuid.UUID
    sku: str | None = None
    product_name: str | None = None
    store_name: str | None = None
    unit_cost: Decimal | None = None
    quantity_on_hand: Decimal
    reorder_point: Decimal
    safety_stock: Decimal
    lead_time_days: int
    inventory_value: Decimal | None = None
    is_low_stock: bool = False
    is_stockout: bool = False
    updated_at: datetime


class InventorySettingsUpdate(APIModel):
    reorder_point: Decimal | None = Field(default=None, ge=0)
    safety_stock: Decimal | None = Field(default=None, ge=0)
    lead_time_days: int | None = Field(default=None, ge=0, le=365)


class MovementCreate(APIModel):
    product_id: uuid.UUID
    store_id: uuid.UUID
    movement_type: MovementType
    quantity: Decimal
    reference: str | None = Field(default=None, max_length=120)
    note: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def _quantity_rules(self) -> MovementCreate:
        if self.movement_type in (MovementType.IN, MovementType.OUT) and self.quantity <= 0:
            raise ValueError("Quantity must be greater than zero for in/out movements.")
        if self.movement_type == MovementType.ADJUST and self.quantity == 0:
            raise ValueError("Adjustment quantity must be a non-zero signed delta.")
        return self


class MovementOut(APIModel):
    id: uuid.UUID
    org_id: uuid.UUID
    product_id: uuid.UUID
    store_id: uuid.UUID
    sku: str | None = None
    product_name: str | None = None
    store_name: str | None = None
    movement_type: MovementType
    quantity: Decimal
    reference: str | None = None
    note: str | None = None
    occurred_at: datetime
