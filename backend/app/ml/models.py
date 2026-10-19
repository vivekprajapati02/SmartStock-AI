"""Forecasting models.

Every model follows the same two-step contract so the backtester can treat
them identically and guarantee no look-ahead:

* ``fit(histories, horizon)`` sees only the training series (cut at the origin).
* ``predict(histories, horizon)`` returns, for each series, ``horizon`` daily
  forecasts for the days *after* the last observation it was given.

Baselines are local (one series at a time). LightGBM is a global, direct
multi-horizon model trained across all series on scale-free targets.
"""

from __future__ import annotations

from collections.abc import Hashable, Mapping
from typing import Any

import numpy as np
import pandas as pd

Histories = Mapping[Hashable, pd.Series]
Predictions = dict[Hashable, np.ndarray]


class Forecaster:
    name: str = "base"
    is_baseline: bool = True

    def params(self) -> dict[str, Any]:
        return {}

    def fit(self, histories: Histories, horizon: int) -> Forecaster:
        return self

    def predict(self, histories: Histories, horizon: int) -> Predictions:
        return {
            key: np.clip(self._predict_one(series.to_numpy(dtype=float), horizon), 0, None)
            for key, series in histories.items()
        }

    def _predict_one(self, values: np.ndarray, horizon: int) -> np.ndarray:
        raise NotImplementedError


class SeasonalNaive(Forecaster):
    """Repeat the last full season (default: the last 7 days)."""

    name = "seasonal_naive"

    def __init__(self, season: int = 7) -> None:
        self.season = season

    def params(self) -> dict[str, Any]:
        return {"season": self.season}

    def _predict_one(self, values: np.ndarray, horizon: int) -> np.ndarray:
        if len(values) < self.season:
            return np.full(horizon, float(values.mean()) if len(values) else 0.0)
        last = values[-self.season :]
        return np.resize(last, horizon).astype(float)


class MovingAverage(Forecaster):
    """Flat forecast at the mean of the last ``window`` days."""

    name = "moving_average"

    def __init__(self, window: int = 28) -> None:
        self.window = window

    def params(self) -> dict[str, Any]:
        return {"window": self.window}

    def _predict_one(self, values: np.ndarray, horizon: int) -> np.ndarray:
        recent = values[-self.window :]
        level = float(recent.mean()) if len(recent) else 0.0
        return np.full(horizon, level)


class SimpleExponentialSmoothing(Forecaster):
    """Flat forecast at the exponentially smoothed level."""

    name = "exponential_smoothing"

    def __init__(self, alpha: float = 0.2) -> None:
        if not 0 < alpha <= 1:
            raise ValueError("alpha must be in (0, 1]")
        self.alpha = alpha

    def params(self) -> dict[str, Any]:
        return {"alpha": self.alpha}

    def _predict_one(self, values: np.ndarray, horizon: int) -> np.ndarray:
        if len(values) == 0:
            return np.zeros(horizon)
        level = float(values[0])
        for value in values[1:]:
            level = self.alpha * float(value) + (1 - self.alpha) * level
        return np.full(horizon, level)


# ---------------------------------------------------------------- LightGBM

_LAGS = 7
_LONG = 28
FEATURE_NAMES = (
    [f"lag_{i}" for i in range(1, _LAGS + 1)]
    + ["mean_7", "mean_28", "std_28", "step", "target_dow", "origin_dow", "target_month"]
)


def _origin_features(
    values: np.ndarray, origin: int, dates: pd.DatetimeIndex, steps: np.ndarray
) -> tuple[np.ndarray, float]:
    """Features for forecasting ``steps`` days after position ``origin``.

    Only ``values[: origin + 1]`` is read, so nothing after the origin leaks in.
    Returns the feature matrix and the scale used to normalise the target.
    """
    window = values[origin + 1 - _LONG : origin + 1]
    level = float(window.mean())
    scale = level if level > 0 else 1.0
    lags = values[origin + 1 - _LAGS : origin + 1][::-1] / scale
    mean_7 = float(values[origin + 1 - 7 : origin + 1].mean()) / scale
    std_28 = float(window.std()) / scale
    origin_date = dates[origin]
    target_dates = origin_date + pd.to_timedelta(steps, unit="D")
    n = len(steps)
    features = np.column_stack(
        [
            np.tile(lags, (n, 1)),
            np.full(n, mean_7),
            np.full(n, level / scale),
            np.full(n, std_28),
            steps,
            target_dates.dayofweek.to_numpy(),
            np.full(n, origin_date.dayofweek),
            target_dates.month.to_numpy(),
        ]
    )
    return features, scale


class LightGBMDirect(Forecaster):
    """Global LightGBM regressor predicting each step ahead directly."""

    name = "lightgbm"
    is_baseline = False

    def __init__(
        self,
        *,
        origin_stride: int = 7,
        n_estimators: int = 300,
        learning_rate: float = 0.05,
        num_leaves: int = 31,
        random_state: int = 42,
    ) -> None:
        self.origin_stride = origin_stride
        self.n_estimators = n_estimators
        self.learning_rate = learning_rate
        self.num_leaves = num_leaves
        self.random_state = random_state
        self._model = None
        self._horizon: int | None = None
        self._fallback = MovingAverage()

    def params(self) -> dict[str, Any]:
        return {
            "origin_stride": self.origin_stride,
            "n_estimators": self.n_estimators,
            "learning_rate": self.learning_rate,
            "num_leaves": self.num_leaves,
            "random_state": self.random_state,
            "features": FEATURE_NAMES,
        }

    def fit(self, histories: Histories, horizon: int) -> LightGBMDirect:
        from lightgbm import LGBMRegressor

        steps = np.arange(1, horizon + 1)
        blocks_x: list[np.ndarray] = []
        blocks_y: list[np.ndarray] = []
        for series in histories.values():
            values = series.to_numpy(dtype=float)
            dates = series.index
            last_origin = len(values) - 1 - horizon
            for origin in range(_LONG - 1, last_origin + 1, self.origin_stride):
                x, scale = _origin_features(values, origin, dates, steps)
                blocks_x.append(x)
                blocks_y.append(values[origin + 1 : origin + 1 + horizon] / scale)
        self._horizon = horizon
        if not blocks_x:
            self._model = None
            return self
        model = LGBMRegressor(
            n_estimators=self.n_estimators,
            learning_rate=self.learning_rate,
            num_leaves=self.num_leaves,
            random_state=self.random_state,
            deterministic=True,
            force_row_wise=True,
            n_jobs=1,
            verbose=-1,
        )
        model.fit(np.vstack(blocks_x), np.concatenate(blocks_y))
        self._model = model
        return self

    def predict(self, histories: Histories, horizon: int) -> Predictions:
        if self._horizon != horizon:
            raise RuntimeError("fit() must be called with the same horizon first")
        if self._model is None:
            return self._fallback.predict(histories, horizon)
        steps = np.arange(1, horizon + 1)
        out: Predictions = {}
        for key, series in histories.items():
            values = series.to_numpy(dtype=float)
            if len(values) < _LONG:
                out[key] = self._fallback.predict({key: series}, horizon)[key]
                continue
            x, scale = _origin_features(values, len(values) - 1, series.index, steps)
            out[key] = np.clip(self._model.predict(x) * scale, 0, None)
        return out


BASELINES = (SeasonalNaive, MovingAverage, SimpleExponentialSmoothing)


def default_models() -> list[Forecaster]:
    return [SeasonalNaive(), MovingAverage(), SimpleExponentialSmoothing(), LightGBMDirect()]


def model_by_name(name: str) -> Forecaster:
    for model in default_models():
        if model.name == name:
            return model
    raise KeyError(name)
