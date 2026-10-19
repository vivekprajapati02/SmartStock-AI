"""Catalogue schemas: categories, suppliers, and stores."""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import EmailStr, Field

from app.schemas.common import APIModel


class CategoryCreate(APIModel):
    name: str = Field(min_length=1, max_length=120)


class CategoryUpdate(APIModel):
    name: str = Field(min_length=1, max_length=120)


class CategoryOut(APIModel):
    id: uuid.UUID
    org_id: uuid.UUID
    name: str
    created_at: datetime


class SupplierCreate(APIModel):
    name: str = Field(min_length=1, max_length=200)
    contact_email: EmailStr | None = None
    phone: str | None = Field(default=None, max_length=40)
    lead_time_days: int = Field(default=7, ge=0, le=365)


class SupplierUpdate(APIModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    contact_email: EmailStr | None = None
    phone: str | None = Field(default=None, max_length=40)
    lead_time_days: int | None = Field(default=None, ge=0, le=365)


class SupplierOut(APIModel):
    id: uuid.UUID
    org_id: uuid.UUID
    name: str
    contact_email: str | None = None
    phone: str | None = None
    lead_time_days: int
    created_at: datetime


class StoreCreate(APIModel):
    name: str = Field(min_length=1, max_length=200)
    location: str | None = Field(default=None, max_length=255)


class StoreUpdate(APIModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    location: str | None = Field(default=None, max_length=255)


class StoreOut(APIModel):
    id: uuid.UUID
    org_id: uuid.UUID
    name: str
    location: str | None = None
    created_at: datetime
