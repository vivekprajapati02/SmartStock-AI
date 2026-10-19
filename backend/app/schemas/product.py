"""Product schemas."""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import Field

from app.schemas.common import APIModel


class ProductCreate(APIModel):
    sku: str = Field(min_length=1, max_length=64)
    name: str = Field(min_length=1, max_length=255)
    category_id: uuid.UUID | None = None
    supplier_id: uuid.UUID | None = None
    unit: str = Field(default="unit", min_length=1, max_length=32)
    unit_cost: Decimal = Field(default=Decimal("0"), ge=0)
    unit_price: Decimal = Field(default=Decimal("0"), ge=0)
    is_active: bool = True


class ProductUpdate(APIModel):
    sku: str | None = Field(default=None, min_length=1, max_length=64)
    name: str | None = Field(default=None, min_length=1, max_length=255)
    category_id: uuid.UUID | None = None
    supplier_id: uuid.UUID | None = None
    unit: str | None = Field(default=None, min_length=1, max_length=32)
    unit_cost: Decimal | None = Field(default=None, ge=0)
    unit_price: Decimal | None = Field(default=None, ge=0)
    is_active: bool | None = None


class ProductOut(APIModel):
    id: uuid.UUID
    org_id: uuid.UUID
    sku: str
    name: str
    category_id: uuid.UUID | None = None
    supplier_id: uuid.UUID | None = None
    unit: str
    unit_cost: Decimal
    unit_price: Decimal
    is_active: bool
    created_at: datetime
