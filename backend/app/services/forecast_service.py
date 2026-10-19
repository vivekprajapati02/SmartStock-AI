"""Backtesting, model selection and forecast generation for an organisation.

* ``run_backtest`` evaluates every model on chronological folds and stores one
  ``model_runs`` row per model (``params.kind = "backtest"``, shared
  ``group_id``, measured metrics) plus the last fold's predictions alongside
  the actuals in ``forecasts``.
* ``generate`` refits the model selected by the latest backtest for that
  horizon on all history and stores future forecasts (``kind = "forecast"``).

Nothing here invents numbers: metrics come from scoring stored sales.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal

import pandas as pd
from sqlalchemy import delete, func, insert, select
from sqlalchemy.orm import Session

from app.core.errors import NotFoundError, UnprocessableError
from app.db.session import set_org_context
from app.ml.backtest import (
    MIN_TRAIN_DAYS,
    InsufficientHistoryError,
)
from app.ml.backtest import (
    run_backtest as ml_run_backtest,
)
from app.ml.models import default_models, model_by_name
from app.ml.series import load_daily_series
from app.models.catalog import Store
from app.models.forecasting import Forecast, ModelRun
from app.models.inventory import SalesHistory
from app.models.organization import Organization
from app.models.product import Product
from app.schemas.forecasting import (
    ActualVsPredicted,
    ComparisonOut,
    DayQuantity,
    ForecastList,
    ForecastPoint,
    ForecastSeries,
    Metrics,
    ModelRunOut,
)

BACKTEST = "backtest"
FORECAST = "forecast"


def _q(value: float) -> Decimal:
    return Decimal(str(round(float(value), 3)))


def run_out(run: ModelRun) -> ModelRunOut:
    params = dict(run.params or {})
    group = params.get("group_id")
    return ModelRunOut(
        id=run.id,
        model_name=run.model_name,
        kind=params.get("kind", BACKTEST),
        horizon=run.horizon,
        group_id=uuid.UUID(group) if group else None,
        selected=bool(params.get("selected", False)),
        is_baseline=bool(params.get("is_baseline", True)),
        metrics=Metrics.model_validate(run.metrics) if run.metrics else None,
        params=params,
        dataset_start=run.dataset_start,
        dataset_end=run.dataset_end,
        trained_at=run.trained_at,
    )


# ---------------------------------------------------------------- backtest


def run_backtest(
    db: Session, *, org_id: uuid.UUID, horizon: int, folds: int = 3
) -> ComparisonOut:
    set_org_context(db, org_id)
    series, start, end = load_daily_series(db, org_id=org_id)
    if end is None:
        raise UnprocessableError("No sales history yet. Import sales before running a backtest.")
    try:
        result = ml_run_backtest(
            series,
            end=end,
            horizon=horizon,
            folds=folds,
            model_factories=[type(m) for m in default_models()],
        )
    except InsufficientHistoryError as exc:
        raise UnprocessableError(str(exc)) from exc

    selected = result.selected
    group_id = uuid.uuid4()
    now = datetime.now(UTC)
    for result_model in result.models:
        run = ModelRun(
            id=uuid.uuid4(),
            org_id=org_id,
            model_name=result_model.name,
            horizon=horizon,
            params={
                "kind": BACKTEST,
                "group_id": str(group_id),
                "selected": selected is not None and result_model.name == selected.name,
                "is_baseline": result_model.is_baseline,
                "folds": folds,
                "cutoffs": [c.isoformat() for c in result.cutoffs],
                "n_series": result.n_series,
                "min_train_days": MIN_TRAIN_DAYS,
                "model_params": result_model.params,
            },
            metrics=result_model.metrics,
            dataset_start=start,
            dataset_end=end,
            trained_at=now,
        )
        db.add(run)
        db.flush()
        if result_model.last_fold:
            db.execute(
                insert(Forecast),
                [
                    {
                        "id": uuid.uuid4(),
                        "org_id": org_id,
                        "model_run_id": run.id,
                        "product_id": p.key[0],
                        "store_id": p.key[1],
                        "forecast_date": p.day,
                        "horizon": horizon,
                        "y_true": _q(p.actual),
                        "y_pred": _q(p.predicted),
                    }
                    for p in result_model.last_fold
                ],
            )
    db.commit()
    return get_comparison(db, org_id=org_id, horizon=horizon)


def _latest_group(db: Session, *, org_id: uuid.UUID, horizon: int) -> list[ModelRun]:
    runs = (
        db.execute(
            select(ModelRun)
            .where(ModelRun.org_id == org_id, ModelRun.horizon == horizon)
            .order_by(ModelRun.trained_at.desc(), ModelRun.id.desc())
            .limit(50)
        )
        .scalars()
        .all()
    )
    backtests = [r for r in runs if (r.params or {}).get("kind") == BACKTEST]
    if not backtests:
        return []
    group = backtests[0].params.get("group_id")
    return [r for r in backtests if r.params.get("group_id") == group]


def get_comparison(db: Session, *, org_id: uuid.UUID, horizon: int) -> ComparisonOut:
    set_org_context(db, org_id)
    org = db.get(Organization, org_id)
    is_demo = bool(org.is_demo) if org else False
    group = _latest_group(db, org_id=org_id, horizon=horizon)
    if not group:
        return ComparisonOut(horizon=horizon, is_demo=is_demo)

    outs = sorted(
        (run_out(r) for r in group),
        key=lambda m: (m.metrics is None or m.metrics.wape is None,
                       m.metrics.wape if m.metrics and m.metrics.wape is not None else 0),
    )
    selected = next((m for m in outs if m.selected), None)
    baselines = [m for m in outs if m.is_baseline and m.metrics and m.metrics.wape is not None]
    baseline = baselines[0] if baselines else None
    improvement = None
    if selected and baseline and selected.metrics and selected.metrics.wape is not None:
        if baseline.metrics.wape:
            improvement = (baseline.metrics.wape - selected.metrics.wape) / baseline.metrics.wape

    fva: list[ActualVsPredicted] = []
    if selected:
        rows = db.execute(
            select(
                Forecast.forecast_date,
                func.sum(Forecast.y_true),
                func.sum(Forecast.y_pred),
            )
            .where(Forecast.org_id == org_id, Forecast.model_run_id == selected.id)
            .group_by(Forecast.forecast_date)
            .order_by(Forecast.forecast_date)
        ).all()
        fva = [
            ActualVsPredicted(day=d, actual=float(a or 0), predicted=float(p or 0))
            for d, a, p in rows
        ]

    first = group[0]
    return ComparisonOut(
        horizon=horizon,
        group_id=uuid.UUID(first.params["group_id"]),
        run_at=first.trained_at,
        dataset_start=first.dataset_start,
        dataset_end=first.dataset_end,
        folds=first.params.get("folds"),
        cutoffs=[date.fromisoformat(c) for c in first.params.get("cutoffs", [])],
        n_series=first.params.get("n_series", 0),
        models=outs,
        selected_model=selected.model_name if selected else None,
        best_baseline=baseline.model_name if baseline else None,
        wape_improvement_vs_baseline=improvement,
        forecast_vs_actual=fva,
        is_demo=is_demo,
    )


def list_runs(
    db: Session,
    *,
    org_id: uuid.UUID,
    horizon: int | None,
    kind: str | None,
    limit: int,
    offset: int,
) -> tuple[list[ModelRunOut], int]:
    set_org_context(db, org_id)
    query = select(ModelRun).where(ModelRun.org_id == org_id)
    if horizon is not None:
        query = query.where(ModelRun.horizon == horizon)
    runs = db.execute(
        query.order_by(ModelRun.trained_at.desc(), ModelRun.model_name)
    ).scalars().all()
    outs = [run_out(r) for r in runs]
    if kind is not None:
        outs = [r for r in outs if r.kind == kind]
    return outs[offset : offset + limit], len(outs)


# ---------------------------------------------------------------- forecasts


def generate(db: Session, *, org_id: uuid.UUID, horizon: int) -> ForecastList:
    """Forecast every series with the model the latest backtest selected
    (running that backtest first if this horizon has never been evaluated)."""
    set_org_context(db, org_id)
    group = _latest_group(db, org_id=org_id, horizon=horizon)
    if not group:
        run_backtest(db, org_id=org_id, horizon=horizon)
        group = _latest_group(db, org_id=org_id, horizon=horizon)
    source = next((r for r in group if r.params.get("selected")), None)
    if source is None:
        raise UnprocessableError("The latest backtest did not select a model.")

    series, start, end = load_daily_series(db, org_id=org_id)
    eligible = {k: s for k, s in series.items() if len(s) >= MIN_TRAIN_DAYS}
    if not eligible or end is None:
        raise UnprocessableError(
            f"Need at least {MIN_TRAIN_DAYS} days of sales history per SKU/store to forecast."
        )
    model = model_by_name(source.model_name)
    model.fit(eligible, horizon)
    predictions = model.predict(eligible, horizon)

    run = ModelRun(
        id=uuid.uuid4(),
        org_id=org_id,
        model_name=source.model_name,
        horizon=horizon,
        params={
            "kind": FORECAST,
            "group_id": source.params.get("group_id"),
            "source_run_id": str(source.id),
            "selected": True,
            "is_baseline": source.params.get("is_baseline", True),
            "n_series": len(eligible),
            "model_params": model.params(),
            "backtest_metrics": source.metrics,
        },
        metrics=None,
        dataset_start=start,
        dataset_end=end,
        trained_at=datetime.now(UTC),
    )
    db.add(run)
    db.flush()
    days = [end + timedelta(days=h) for h in range(1, horizon + 1)]
    db.execute(
        insert(Forecast),
        [
            {
                "id": uuid.uuid4(),
                "org_id": org_id,
                "model_run_id": run.id,
                "product_id": key[0],
                "store_id": key[1],
                "forecast_date": day,
                "horizon": horizon,
                "y_true": None,
                "y_pred": _q(value),
            }
            for key, values in predictions.items()
            for day, value in zip(days, values, strict=True)
        ],
    )
    # Keep only the latest forecast run per horizon to bound table growth.
    old_runs = [
        r.id
        for r in db.execute(
            select(ModelRun).where(
                ModelRun.org_id == org_id, ModelRun.horizon == horizon, ModelRun.id != run.id
            )
        ).scalars()
        if (r.params or {}).get("kind") == FORECAST
    ]
    if old_runs:
        db.execute(delete(Forecast).where(Forecast.model_run_id.in_(old_runs)))
        db.execute(delete(ModelRun).where(ModelRun.id.in_(old_runs)))
    db.commit()
    return list_forecasts(db, org_id=org_id, horizon=horizon, limit=50, offset=0)


def _latest_forecast_run(
    db: Session, *, org_id: uuid.UUID, horizon: int | None
) -> ModelRun | None:
    query = select(ModelRun).where(ModelRun.org_id == org_id)
    if horizon is not None:
        query = query.where(ModelRun.horizon == horizon)
    for run in db.execute(
        query.order_by(ModelRun.trained_at.desc(), ModelRun.id.desc())
    ).scalars():
        if (run.params or {}).get("kind") == FORECAST:
            return run
    return None


def list_forecasts(
    db: Session,
    *,
    org_id: uuid.UUID,
    horizon: int | None,
    limit: int,
    offset: int,
    product_id: uuid.UUID | None = None,
    store_id: uuid.UUID | None = None,
) -> ForecastList:
    set_org_context(db, org_id)
    run = _latest_forecast_run(db, org_id=org_id, horizon=horizon)
    if run is None:
        return ForecastList(run=None, items=[], total=0, limit=limit, offset=offset)
    filters = [Forecast.org_id == org_id, Forecast.model_run_id == run.id]
    if product_id is not None:
        filters.append(Forecast.product_id == product_id)
    if store_id is not None:
        filters.append(Forecast.store_id == store_id)
    total = int(
        db.execute(select(func.count()).select_from(Forecast).where(*filters)).scalar_one()
    )
    rows = db.execute(
        select(Forecast, Product.sku, Product.name, Store.name)
        .join(Product, Product.id == Forecast.product_id)
        .join(Store, Store.id == Forecast.store_id)
        .where(*filters)
        .order_by(Product.sku, Store.name, Forecast.forecast_date)
        .limit(limit)
        .offset(offset)
    ).all()
    return ForecastList(
        run=run_out(run),
        items=[
            ForecastPoint(
                product_id=f.product_id,
                store_id=f.store_id,
                sku=sku,
                product_name=pname,
                store_name=sname,
                forecast_date=f.forecast_date,
                quantity=float(f.y_pred),
            )
            for f, sku, pname, sname in rows
        ],
        total=total,
        limit=limit,
        offset=offset,
    )


def forecast_series(
    db: Session,
    *,
    org_id: uuid.UUID,
    product_id: uuid.UUID,
    store_id: uuid.UUID,
    horizon: int | None,
    history_days: int,
) -> ForecastSeries:
    set_org_context(db, org_id)
    product = db.get(Product, product_id)
    store = db.get(Store, store_id)
    if product is None or product.org_id != org_id or store is None or store.org_id != org_id:
        raise NotFoundError("Product or store not found.")

    run = _latest_forecast_run(db, org_id=org_id, horizon=horizon)
    forecast: list[DayQuantity] = []
    if run is not None:
        forecast = [
            DayQuantity(day=d, quantity=float(q))
            for d, q in db.execute(
                select(Forecast.forecast_date, Forecast.y_pred)
                .where(
                    Forecast.org_id == org_id,
                    Forecast.model_run_id == run.id,
                    Forecast.product_id == product_id,
                    Forecast.store_id == store_id,
                )
                .order_by(Forecast.forecast_date)
            ).all()
        ]

    last_day = db.execute(
        select(func.max(SalesHistory.sale_date)).where(SalesHistory.org_id == org_id)
    ).scalar_one()
    history: list[DayQuantity] = []
    if last_day is not None:
        first_day = last_day - timedelta(days=history_days - 1)
        sold = defaultdict(float)
        for d, q in db.execute(
            select(SalesHistory.sale_date, SalesHistory.quantity).where(
                SalesHistory.org_id == org_id,
                SalesHistory.product_id == product_id,
                SalesHistory.store_id == store_id,
                SalesHistory.sale_date >= first_day,
                SalesHistory.sale_date <= last_day,
            )
        ).all():
            sold[d] += float(q)
        history = [
            DayQuantity(day=d.date(), quantity=sold.get(d.date(), 0.0))
            for d in pd.date_range(first_day, last_day, freq="D")
        ]
    return ForecastSeries(
        product_id=product_id,
        store_id=store_id,
        run=run_out(run) if run else None,
        history=history,
        forecast=forecast,
    )
