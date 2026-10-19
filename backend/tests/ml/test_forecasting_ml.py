"""Unit tests for forecasting metrics, models and the backtester."""

from __future__ import annotations

import math
from datetime import date

import numpy as np
import pandas as pd
import pytest

from app.ml import metrics
from app.ml.backtest import (
    MIN_TRAIN_DAYS,
    InsufficientHistoryError,
    ModelResult,
    cutoff_dates,
    run_backtest,
    select_model,
)
from app.ml.models import (
    Forecaster,
    LightGBMDirect,
    MovingAverage,
    SeasonalNaive,
    SimpleExponentialSmoothing,
)

# ---------------------------------------------------------------- metrics


def test_metrics_match_hand_computed_values():
    actual = [10, 0, 5, 5]
    predicted = [8, 1, 5, 9]
    # errors (pred - actual): -2, 1, 0, 4
    assert metrics.mae(actual, predicted) == pytest.approx(7 / 4)
    assert metrics.rmse(actual, predicted) == pytest.approx(math.sqrt(21 / 4))
    assert metrics.wape(actual, predicted) == pytest.approx(7 / 20)
    assert metrics.bias(actual, predicted) == pytest.approx(3 / 20)


def test_perfect_forecast_scores_zero():
    s = metrics.score([3, 4, 5], [3, 4, 5])
    assert s == {"mae": 0.0, "rmse": 0.0, "wape": 0.0, "bias": 0.0, "n_points": 3}


def test_under_forecast_has_negative_bias():
    assert metrics.bias([10, 10], [5, 5]) == pytest.approx(-0.5)


def test_ratio_metrics_are_undefined_without_demand():
    assert metrics.wape([0, 0], [1, 0]) is None
    assert metrics.bias([0, 0], [1, 0]) is None
    assert metrics.mae([0, 0], [1, 0]) == pytest.approx(0.5)


def test_metrics_reject_mismatched_or_empty_input():
    with pytest.raises(ValueError):
        metrics.mae([1, 2], [1])
    with pytest.raises(ValueError):
        metrics.mae([], [])


# ---------------------------------------------------------------- baselines


def _series(values, start="2026-01-01") -> pd.Series:
    return pd.Series(
        np.asarray(values, dtype=float),
        index=pd.date_range(start, periods=len(values), freq="D"),
    )


def test_seasonal_naive_repeats_last_week():
    s = _series(list(range(1, 15)))  # last 7: 8..14
    pred = SeasonalNaive().predict({"k": s}, 10)["k"]
    assert pred.tolist() == [8, 9, 10, 11, 12, 13, 14, 8, 9, 10]


def test_moving_average_is_flat_mean_of_window():
    s = _series([0] * 10 + [4] * 28)
    pred = MovingAverage(window=28).predict({"k": s}, 3)["k"]
    assert pred.tolist() == [4, 4, 4]


def test_exponential_smoothing_hand_computed():
    s = _series([10, 20, 30])
    # level: 10 -> 0.5*20+0.5*10=15 -> 0.5*30+0.5*15=22.5
    pred = SimpleExponentialSmoothing(alpha=0.5).predict({"k": s}, 2)["k"]
    assert pred.tolist() == [22.5, 22.5]


def test_forecasts_are_never_negative():
    s = _series([-5.0] * 30)
    assert (MovingAverage().predict({"k": s}, 4)["k"] >= 0).all()


# ---------------------------------------------------------------- backtest


class SpyModel(Forecaster):
    """Records the last date it was shown; predicts the last observed value."""

    name = "spy"
    seen: list[pd.Timestamp] = []

    def fit(self, histories, horizon):
        SpyModel.seen.extend(s.index[-1] for s in histories.values())
        return self

    def predict(self, histories, horizon):
        SpyModel.seen.extend(s.index[-1] for s in histories.values())
        return {k: np.full(horizon, s.iloc[-1]) for k, s in histories.items()}


def test_cutoffs_are_chronological_and_end_at_dataset_end():
    assert cutoff_dates(date(2026, 3, 31), 7, 3) == [
        date(2026, 3, 10),
        date(2026, 3, 17),
        date(2026, 3, 24),
    ]


def test_backtest_never_shows_future_data_to_models():
    SpyModel.seen = []
    s = _series(np.arange(200))
    end = s.index[-1].date()
    result = run_backtest(
        {"a": s}, end=end, horizon=14, folds=3, model_factories=[SpyModel]
    )
    cutoffs = [pd.Timestamp(c) for c in result.cutoffs]
    # Each fit/predict saw data ending exactly at a cutoff, never later.
    assert sorted(set(SpyModel.seen)) == cutoffs
    # Last-value forecast on a +1/day series errs by 1..14 each fold.
    expected_mae = np.mean(np.arange(1, 15))
    assert result.models[0].metrics["mae"] == pytest.approx(expected_mae)
    assert result.models[0].metrics["n_points"] == 14 * 3
    last = result.models[0].last_fold
    assert [p.day for p in last][0] == (cutoffs[-1] + pd.Timedelta(days=1)).date()
    assert last[-1].day == end


def test_series_without_enough_history_are_excluded_consistently():
    long = _series(np.ones(200))
    short = _series(np.ones(30), start="2026-06-20")  # ends with `long`
    assert long.index[-1] == short.index[-1]
    result = run_backtest(
        {"long": long, "short": short},
        end=long.index[-1].date(),
        horizon=7,
        folds=2,
        model_factories=[MovingAverage],
    )
    assert result.n_series == 1


def test_insufficient_history_raises():
    s = _series(np.ones(MIN_TRAIN_DAYS))
    with pytest.raises(InsufficientHistoryError):
        run_backtest(
            {"a": s}, end=s.index[-1].date(), horizon=30, folds=3,
            model_factories=[MovingAverage],
        )


def _result(name, wape, mae, baseline=True):
    return ModelResult(name, baseline, {}, {"wape": wape, "mae": mae})


def test_selection_prefers_baseline_unless_challenger_strictly_wins():
    baseline = _result("moving_average", 0.30, 2.0)
    assert select_model([baseline, _result("lightgbm", 0.30, 2.0, False)]).name == (
        "moving_average"
    )
    assert select_model([baseline, _result("lightgbm", 0.31, 1.0, False)]).name == (
        "moving_average"
    )
    assert select_model([baseline, _result("lightgbm", 0.25, 2.5, False)]).name == "lightgbm"
    assert select_model(
        [_result("seasonal_naive", 0.4, 1), _result("moving_average", 0.3, 9)]
    ).name == "moving_average"


def test_lightgbm_is_deterministic_and_well_formed():
    rng = np.random.default_rng(0)
    days = 240
    weekly = np.tile([5, 6, 7, 8, 12, 15, 9], days // 7 + 1)[:days]
    histories = {
        k: _series(weekly * scale + rng.poisson(1, days)) for k, scale in (("a", 1), ("b", 3))
    }
    first = LightGBMDirect(n_estimators=50).fit(histories, 14).predict(histories, 14)
    second = LightGBMDirect(n_estimators=50).fit(histories, 14).predict(histories, 14)
    for key in histories:
        assert first[key].shape == (14,)
        assert (first[key] >= 0).all()
        np.testing.assert_allclose(first[key], second[key])
    # Scale-free targets: the 3x series gets roughly 3x forecasts.
    ratio = first["b"].sum() / first["a"].sum()
    assert 2.0 < ratio < 4.0


def test_lightgbm_requires_fit_for_the_same_horizon():
    s = {"a": _series(np.ones(120))}
    model = LightGBMDirect(n_estimators=10).fit(s, 7)
    with pytest.raises(RuntimeError):
        model.predict(s, 14)
