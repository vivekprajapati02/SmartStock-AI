"""Purchase order schemas."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal

from pydantic import Field, field_validator

from app.models.enums import PurchaseOrderStatus
from app.schemas.common import APIModel


class POItemIn(APIModel):
    product_id: uuid.UUID
    quantity_ordered: Decimal = Field(gt=0, max_digits=14, decimal_places=3)


def _unique_products(items: list[POItemIn]) -> list[POItemIn]:
    ids = [i.product_id for i in items]
    if len(ids) != len(set(ids)):
        raise ValueError("Each product may appear only once per purchase order.")
    return items


class POCreate(APIModel):
    supplier_id: uuid.UUID
    store_id: uuid.UUID
    reference: str | None = Field(default=None, max_length=120)
    expected_date: date | None = None
    items: list[POItemIn] = Field(min_length=1, max_length=500)

    _unique = field_validator("items")(_unique_products)


class POUpdate(APIModel):
    """Draft orders only. Supplying ``items`` replaces all lines."""

    reference: str | None = Field(default=None, max_length=120)
    expected_date: date | None = None
    items: list[POItemIn] | None = Field(default=None, min_length=1, max_length=500)

    @field_validator("items")
    @classmethod
    def _unique(cls, items: list[POItemIn] | None) -> list[POItemIn] | None:
        return None if items is None else _unique_products(items)


class ReceiveLine(APIModel):
    item_id: uuid.UUID
    quantity: Decimal = Field(gt=0, max_digits=14, decimal_places=3)


class ReceiveRequest(APIModel):
    lines: list[ReceiveLine] = Field(min_length=1)
    note: str | None = Field(default=None, max_length=500)

    @field_validator("lines")
    @classmethod
    def _unique_lines(cls, lines: list[ReceiveLine]) -> list[ReceiveLine]:
        ids = [line.item_id for line in lines]
        if len(ids) != len(set(ids)):
            raise ValueError("Each order line may appear only once per receipt.")
        return lines


class POItemOut(APIModel):
    id: uuid.UUID
    product_id: uuid.UUID
    sku: str | None = None
    product_name: str | None = None
    unit_cost: Decimal | None = None
    quantity_ordered: Decimal
    quantity_received: Decimal
    quantity_remaining: Decimal


class POOut(APIModel):
    id: uuid.UUID
    org_id: uuid.UUID
    supplier_id: uuid.UUID
    supplier_name: str | None = None
    store_id: uuid.UUID
    store_name: str | None = None
    status: PurchaseOrderStatus
    reference: str | None = None
    expected_date: date | None = None
    created_by: uuid.UUID | None = None
    approved_by: uuid.UUID | None = None
    line_count: int
    total_ordered: Decimal
    total_received: Decimal
    # Sum of quantity_ordered x the product's current unit cost.
    estimated_cost: Decimal
    created_at: datetime
    updated_at: datetime


class PODetail(POOut):
    items: list[POItemOut]


class FromRecommendationsRequest(APIModel):
    store_id: uuid.UUID
    service_level: float = Field(default=0.95, ge=0.5, le=0.999)
    review_days: int = Field(default=7, ge=1, le=90)


class SkippedItem(APIModel):
    product_id: uuid.UUID
    sku: str
    reason: str


class FromRecommendationsResult(APIModel):
    created: list[POOut]
    skipped: list[SkippedItem]
