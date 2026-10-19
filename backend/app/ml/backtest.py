"""Rolling-origin backtesting with strict chronological splits.

For each fold the cutoff date splits every series: models are fitted and
asked to predict using data up to and including the cutoff, then scored on the
``horizon`` days that follow. Nothing after a cutoff is ever passed to a model.
"""

from __future__ import annotations

from collections.abc import Callable, Hashable, Mapping
from dataclasses import dataclass, field
from datetime import date

import numpy as np
import pandas as pd

from app.ml.metrics import score
from app.ml.models import Forecaster

# Series need this many days before a cutoff to be scored in that fold.
MIN_TRAIN_DAYS = 56


@dataclass
class FoldPoint:
    key: Hashable
    day: date
    actual: float
    predicted: float


@dataclass
class ModelResult:
    name: str
    is_baseline: bool
    params: dict
    metrics: dict
    last_fold: list[FoldPoint] = field(default_factory=list)


@dataclass
class BacktestResult:
    horizon: int
    cutoffs: list[date]
    n_series: int
    models: list[ModelResult]

    @property
    def selected(self) -> ModelResult | None:
        return select_model(self.models)


class InsufficientHistoryError(ValueError):
    """No series has enough history for the requested horizon and folds."""


def cutoff_dates(end: date, horizon: int, folds: int) -> list[date]:
    """Oldest first; the last fold's test window ends exactly at ``end``."""
    end_ts = pd.Timestamp(end)
    return [
        (end_ts - pd.Timedelta(days=horizon * k)).date() for k in range(folds, 0, -1)
    ]


def eligible_series(
    series: Mapping[Hashable, pd.Series], first_cutoff: date
) -> dict[Hashable, pd.Series]:
    """Series with enough history before the first cutoff, so every model is
    scored on exactly the same series in every fold."""
    cutoff = pd.Timestamp(first_cutoff)
    return {
        key: s
        for key, s in series.items()
        if len(s.loc[:cutoff]) >= MIN_TRAIN_DAYS and s.index[-1] > cutoff
    }


def run_backtest(
    series: Mapping[Hashable, pd.Series],
    *,
    end: date,
    horizon: int,
    folds: int,
    model_factories: list[Callable[[], Forecaster]],
) -> BacktestResult:
    cutoffs = cutoff_dates(end, horizon, folds)
    pool = eligible_series(series, cutoffs[0])
    if not pool:
        raise InsufficientHistoryError(
            f"Need at least {MIN_TRAIN_DAYS + horizon * folds} days of sales history "
            f"for a {horizon}-day backtest with {folds} folds."
        )

    actual_all: dict[str, list[np.ndarray]] = {}
    pred_all: dict[str, list[np.ndarray]] = {}
    results: dict[str, ModelResult] = {}

    for fold_index, cutoff in enumerate(cutoffs):
        cut = pd.Timestamp(cutoff)
        train = {key: s.loc[:cut] for key, s in pool.items()}
        test_index = pd.date_range(cut + pd.Timedelta(days=1), periods=horizon, freq="D")
        actuals = {key: s.reindex(test_index).to_numpy(dtype=float) for key, s in pool.items()}
        is_last = fold_index == len(cutoffs) - 1

        for factory in model_factories:
            model = factory()
            model.fit(train, horizon)
            predictions = model.predict(train, horizon)
            result = results.setdefault(
                model.name,
                ModelResult(model.name, model.is_baseline, model.params(), {}),
            )
            for key in pool:
                pred = np.asarray(predictions[key], dtype=float)
                if pred.shape != (horizon,):
                    raise ValueError(f"{model.name} returned {pred.shape} for horizon {horizon}")
                actual_all.setdefault(model.name, []).append(actuals[key])
                pred_all.setdefault(model.name, []).append(pred)
                if is_last:
                    result.last_fold.extend(
                        FoldPoint(key, d.date(), float(a), float(p))
                        for d, a, p in zip(test_index, actuals[key], pred, strict=True)
                    )

    for name, result in results.items():
        result.metrics = score(np.concatenate(actual_all[name]), np.concatenate(pred_all[name]))

    return BacktestResult(
        horizon=horizon,
        cutoffs=cutoffs,
        n_series=len(pool),
        models=list(results.values()),
    )


def _rank(result: ModelResult) -> tuple:
    wape = result.metrics.get("wape")
    return (wape is None, wape if wape is not None else 0.0, result.metrics["mae"])


def select_model(models: list[ModelResult]) -> ModelResult | None:
    """Best baseline by WAPE (then MAE). A non-baseline model replaces it only
    if it is strictly better on that ranking."""
    baselines = sorted((m for m in models if m.is_baseline), key=_rank)
    challengers = sorted((m for m in models if not m.is_baseline), key=_rank)
    best = baselines[0] if baselines else None
    if challengers and (best is None or _rank(challengers[0]) < _rank(best)):
        return challengers[0]
    return best


def best_baseline(models: list[ModelResult]) -> ModelResult | None:
    baselines = sorted((m for m in models if m.is_baseline), key=_rank)
    return baselines[0] if baselines else None
