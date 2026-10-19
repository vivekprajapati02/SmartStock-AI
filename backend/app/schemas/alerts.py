"""Stock alert schemas."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from app.models.enums import AlertSeverity, AlertStatus, AlertType
from app.schemas.common import APIModel


class AlertOut(APIModel):
    id: uuid.UUID
    product_id: uuid.UUID
    store_id: uuid.UUID
    sku: str | None = None
    product_name: str | None = None
    store_name: str | None = None
    alert_type: AlertType
    severity: AlertSeverity
    status: AlertStatus
    message: str
    created_at: datetime
    updated_at: datetime


class AlertUpdate(APIModel):
    status: Literal["acknowledged", "resolved", "dismissed"]


class EvaluateRequest(APIModel):
    service_level: float = 0.95
    review_days: int = 7


class EvaluateResult(APIModel):
    created: int
    updated: int
    resolved: int
    open_total: int
    evaluated_items: int
