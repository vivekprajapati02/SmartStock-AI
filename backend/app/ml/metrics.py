"""Forecast accuracy metrics.

Conventions (error = forecast - actual):

* MAE   = mean(|error|)
* RMSE  = sqrt(mean(error^2))
* WAPE  = sum(|error|) / sum(|actual|)       (None when actuals sum to 0)
* Bias  = sum(error) / sum(|actual|)         (positive = over-forecasting)
"""

from __future__ import annotations

import math
from collections.abc import Sequence

import numpy as np


def _arrays(actual: Sequence[float], predicted: Sequence[float]) -> tuple[np.ndarray, np.ndarray]:
    a = np.asarray(actual, dtype=float)
    p = np.asarray(predicted, dtype=float)
    if a.shape != p.shape:
        raise ValueError("actual and predicted must have the same length")
    if a.size == 0:
        raise ValueError("cannot score an empty forecast")
    return a, p


def mae(actual: Sequence[float], predicted: Sequence[float]) -> float:
    a, p = _arrays(actual, predicted)
    return float(np.mean(np.abs(p - a)))


def rmse(actual: Sequence[float], predicted: Sequence[float]) -> float:
    a, p = _arrays(actual, predicted)
    return float(math.sqrt(np.mean((p - a) ** 2)))


def wape(actual: Sequence[float], predicted: Sequence[float]) -> float | None:
    a, p = _arrays(actual, predicted)
    denom = float(np.sum(np.abs(a)))
    if denom == 0:
        return None
    return float(np.sum(np.abs(p - a)) / denom)


def bias(actual: Sequence[float], predicted: Sequence[float]) -> float | None:
    a, p = _arrays(actual, predicted)
    denom = float(np.sum(np.abs(a)))
    if denom == 0:
        return None
    return float(np.sum(p - a) / denom)


def score(actual: Sequence[float], predicted: Sequence[float]) -> dict[str, float | int | None]:
    """All metrics plus the number of scored points."""
    return {
        "mae": mae(actual, predicted),
        "rmse": rmse(actual, predicted),
        "wape": wape(actual, predicted),
        "bias": bias(actual, predicted),
        "n_points": len(actual),
    }
