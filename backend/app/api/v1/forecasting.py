"""Forecast and model-evaluation endpoints."""

from __future__ import annotations

import uuid
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser, require_roles
from app.core.errors import UnprocessableError
from app.core.rbac import Role
from app.db.session import get_db
from app.models.user import User
from app.schemas.common import Page
from app.schemas.forecasting import (
    ALLOWED_HORIZONS,
    BacktestRequest,
    ComparisonOut,
    ForecastList,
    ForecastSeries,
    GenerateRequest,
    ModelRunOut,
)
from app.services import forecast_service

ManagerUser = Annotated[User, Depends(require_roles(Role.OWNER, Role.ADMIN, Role.MANAGER))]


def _check(horizon: int | None) -> int | None:
    if horizon is not None and horizon not in ALLOWED_HORIZONS:
        raise UnprocessableError(
            f"Horizon must be one of {', '.join(map(str, ALLOWED_HORIZONS))}."
        )
    return horizon


def optional_horizon(horizon: int | None = Query(default=None)) -> int | None:
    return _check(horizon)


def required_horizon(horizon: int = Query(default=30)) -> int:
    return _check(horizon)  # type: ignore[return-value]


OptionalHorizon = Annotated[int | None, Depends(optional_horizon)]
RequiredHorizon = Annotated[int, Depends(required_horizon)]

forecasts_router = APIRouter(tags=["forecasts"])
models_router = APIRouter(tags=["models"])


@forecasts_router.post("/forecasts:generate", response_model=ForecastList)
def generate_forecasts(
    payload: GenerateRequest,
    user: ManagerUser,
    db: Annotated[Session, Depends(get_db)],
) -> ForecastList:
    """Forecast every SKU/store with the model selected by the latest backtest
    for this horizon (a backtest runs first if none exists)."""
    return forecast_service.generate(db, org_id=user.org_id, horizon=payload.horizon)


@forecasts_router.get("/forecasts", response_model=ForecastList)
def list_forecasts(
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    horizon: OptionalHorizon,
    product_id: uuid.UUID | None = Query(default=None),
    store_id: uuid.UUID | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
) -> ForecastList:
    return forecast_service.list_forecasts(
        db,
        org_id=user.org_id,
        horizon=horizon,
        product_id=product_id,
        store_id=store_id,
        limit=limit,
        offset=offset,
    )


@forecasts_router.get("/forecasts/series", response_model=ForecastSeries)
def forecast_series(
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    product_id: uuid.UUID,
    store_id: uuid.UUID,
    horizon: OptionalHorizon,
    history_days: int = Query(default=60, ge=7, le=365),
) -> ForecastSeries:
    return forecast_service.forecast_series(
        db,
        org_id=user.org_id,
        product_id=product_id,
        store_id=store_id,
        horizon=horizon,
        history_days=history_days,
    )


@models_router.post("/models:backtest", response_model=ComparisonOut)
def backtest(
    payload: BacktestRequest,
    user: ManagerUser,
    db: Annotated[Session, Depends(get_db)],
) -> ComparisonOut:
    """Chronological rolling-origin backtest of every model; results persist."""
    return forecast_service.run_backtest(
        db, org_id=user.org_id, horizon=payload.horizon, folds=payload.folds
    )


@models_router.get("/models/runs", response_model=Page[ModelRunOut])
def list_model_runs(
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    horizon: OptionalHorizon,
    kind: Literal["backtest", "forecast"] | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> Page[ModelRunOut]:
    items, total = forecast_service.list_runs(
        db, org_id=user.org_id, horizon=horizon, kind=kind, limit=limit, offset=offset
    )
    return Page[ModelRunOut](items=items, total=total, limit=limit, offset=offset)


@models_router.get("/models/comparison", response_model=ComparisonOut)
def model_comparison(
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    horizon: RequiredHorizon,
) -> ComparisonOut:
    """Latest persisted backtest for the horizon; empty if none has run."""
    return forecast_service.get_comparison(db, org_id=user.org_id, horizon=horizon)


__all__ = ["forecasts_router", "models_router", "ALLOWED_HORIZONS"]
