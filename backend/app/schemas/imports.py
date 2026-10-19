"""CSV import schemas: per-row validation and batch responses."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import Field, field_validator

from app.models.enums import ImportStatus
from app.schemas.common import APIModel

# Columns every sales CSV must contain (header names are case-insensitive).
REQUIRED_COLUMNS = ("sku", "store", "sale_date", "quantity")


class SalesRowIn(APIModel):
    """One CSV data row. Types are checked here; references (SKU/store) and
    duplicates are checked by the import service."""

    sku: str = Field(min_length=1, max_length=64)
    store: str = Field(min_length=1, max_length=200)
    sale_date: date
    quantity: Decimal = Field(ge=0, max_digits=14, decimal_places=3)

    @field_validator("sku", "store", mode="before")
    @classmethod
    def _strip(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value

    @field_validator("sale_date", mode="before")
    @classmethod
    def _iso_date(cls, value: object) -> object:
        # Only accept ISO dates (YYYY-MM-DD) to avoid day/month ambiguity.
        if isinstance(value, str):
            text = value.strip()
            try:
                return date.fromisoformat(text)
            except ValueError as exc:
                raise ValueError("Use the ISO date format YYYY-MM-DD.") from exc
        return value

    @field_validator("sale_date")
    @classmethod
    def _not_future(cls, value: date) -> date:
        if value > date.today():
            raise ValueError("Sale date cannot be in the future.")
        return value


class ImportRowError(APIModel):
    """A problem with one row (or the whole file when ``row`` is null).

    ``row`` is the 1-based data row number; the line in the file is ``row + 1``
    because of the header.
    """

    row: int | None = None
    column: str | None = None
    value: str | None = None
    message: str
    kind: Literal["invalid", "duplicate", "file"] = "invalid"


class ImportBatchOut(APIModel):
    id: uuid.UUID
    org_id: uuid.UUID
    filename: str
    status: ImportStatus
    total_rows: int
    valid_rows: int
    invalid_rows: int
    duplicate_rows: int
    error_count: int = 0
    created_at: datetime


class ImportBatchDetail(ImportBatchOut):
    errors: list[ImportRowError] = Field(default_factory=list)
    errors_truncated: bool = False
