"""Forecasting and model-evaluation schemas. Every metric is measured."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import Field, field_validator

from app.schemas.common import APIModel

ALLOWED_HORIZONS = (7, 14, 30, 90)


def _check_horizon(value: int) -> int:
    if value not in ALLOWED_HORIZONS:
        raise ValueError(f"Horizon must be one of {', '.join(map(str, ALLOWED_HORIZONS))}.")
    return value


class BacktestRequest(APIModel):
    horizon: int = 30
    folds: int = Field(default=3, ge=1, le=6)

    _horizon = field_validator("horizon")(_check_horizon)


class GenerateRequest(APIModel):
    horizon: int = 30

    _horizon = field_validator("horizon")(_check_horizon)


class Metrics(APIModel):
    mae: float
    rmse: float
    wape: float | None = None
    bias: float | None = None
    n_points: int


class ModelRunOut(APIModel):
    id: uuid.UUID
    model_name: str
    kind: Literal["backtest", "forecast"]
    horizon: int
    group_id: uuid.UUID | None = None
    selected: bool = False
    is_baseline: bool = True
    metrics: Metrics | None = None
    params: dict = Field(default_factory=dict)
    dataset_start: date | None = None
    dataset_end: date | None = None
    trained_at: datetime


class ActualVsPredicted(APIModel):
    day: date
    actual: float
    predicted: float


class ComparisonOut(APIModel):
    """Latest backtest for a horizon. ``models`` is empty if none has run."""

    horizon: int
    group_id: uuid.UUID | None = None
    run_at: datetime | None = None
    dataset_start: date | None = None
    dataset_end: date | None = None
    folds: int | None = None
    cutoffs: list[date] = Field(default_factory=list)
    n_series: int = 0
    models: list[ModelRunOut] = Field(default_factory=list)
    selected_model: str | None = None
    best_baseline: str | None = None
    # (best baseline WAPE - selected WAPE) / best baseline WAPE; 0 if a baseline won.
    wape_improvement_vs_baseline: float | None = None
    # Selected model's last backtest fold, summed over all series per day.
    forecast_vs_actual: list[ActualVsPredicted] = Field(default_factory=list)
    is_demo: bool = False


class ForecastPoint(APIModel):
    product_id: uuid.UUID
    store_id: uuid.UUID
    sku: str | None = None
    product_name: str | None = None
    store_name: str | None = None
    forecast_date: date
    quantity: float


class ForecastList(APIModel):
    run: ModelRunOut | None = None
    items: list[ForecastPoint]
    total: int
    limit: int
    offset: int


class DayQuantity(APIModel):
    day: date
    quantity: float


class ForecastSeries(APIModel):
    """Recent actual sales plus the latest stored forecast for one SKU/store."""

    product_id: uuid.UUID
    store_id: uuid.UUID
    run: ModelRunOut | None = None
    history: list[DayQuantity]
    forecast: list[DayQuantity]
