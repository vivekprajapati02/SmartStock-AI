"""Forecasting artefacts: model runs (backtest metadata) and stored forecasts."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import (
    JSON,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, OrgScopedMixin, TimestampMixin, UUIDPrimaryKeyMixin


class ModelRun(Base, UUIDPrimaryKeyMixin, OrgScopedMixin, TimestampMixin):
    """One model evaluation. ``metrics`` holds measured MAE/RMSE/WAPE/bias."""

    __tablename__ = "model_runs"

    model_name: Mapped[str] = mapped_column(String(80), nullable=False)
    horizon: Mapped[int] = mapped_column(Integer, nullable=False)
    params: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    metrics: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    dataset_start: Mapped[date | None] = mapped_column(Date, nullable=True)
    dataset_end: Mapped[date | None] = mapped_column(Date, nullable=True)
    trained_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


class Forecast(Base, UUIDPrimaryKeyMixin, OrgScopedMixin, TimestampMixin):
    """A stored prediction, optionally paired with the actual value once known."""

    __tablename__ = "forecasts"

    model_run_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("model_runs.id", ondelete="CASCADE"), nullable=True, index=True
    )
    product_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("products.id", ondelete="CASCADE"), nullable=False, index=True
    )
    store_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("stores.id", ondelete="CASCADE"), nullable=False, index=True
    )
    forecast_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    horizon: Mapped[int] = mapped_column(Integer, nullable=False)
    y_true: Mapped[Decimal | None] = mapped_column(Numeric(14, 3), nullable=True)
    y_pred: Mapped[Decimal] = mapped_column(Numeric(14, 3), nullable=False)
