# Forecasting and Model Evaluation

SmartStock AI forecasts daily demand per SKU and store from stored
`sales_history`. Every accuracy figure shown anywhere in the product is
measured by backtesting on the organisation's own stored data and read back
from the database. No accuracy is assumed, estimated or hardcoded.

Code: `backend/app/ml/` (metrics, series, models, backtest) and
`backend/app/services/forecast_service.py` (persistence and selection).

## Data preparation

`app/ml/series.py` builds one daily series per product/store:

- runs from that series' first recorded sale to the organisation's last sales
  date;
- days without a `sales_history` row are treated as **zero sales**;
- quantities are summed per day.

There is no outlier removal, promotion flag or stockout correction yet. A day
on which an item was out of stock counts as zero demand, which biases forecasts
down for items that frequently stock out.

## Models

| Name | Type | Forecast |
|------|------|----------|
| `seasonal_naive` | Baseline | Repeats the last 7 days |
| `moving_average` | Baseline | Flat at the mean of the last 28 days |
| `exponential_smoothing` | Baseline | Flat at the simple exponentially smoothed level (alpha = 0.2) |
| `lightgbm` | Machine learning | Global direct multi-horizon gradient boosting |

All forecasts are clipped at zero.

### LightGBM details

One model is trained across all series for a given horizon (a *global*
model). Each training row is a (forecast origin, step ahead) pair:

- **Features**, computed only from data up to and including the origin: last
  7 daily values, 7-day mean, 28-day mean and standard deviation (all divided
  by the series' 28-day mean so series of different sizes share one model),
  the step ahead (1..H), target day of week, origin day of week, and target
  month.
- **Target**: the actual sales `step` days after the origin, divided by the
  same scale. Predictions are multiplied back.
- Origins are sampled every 7 days to keep training fast.
- `n_estimators=300`, `learning_rate=0.05`, `num_leaves=31`,
  `random_state=42`, `deterministic=True`, single-threaded, so runs are
  reproducible.

## Backtesting

`app/ml/backtest.py` performs a rolling-origin evaluation with strict
chronological splits:

1. `dataset_end` is the last sales date. For `folds = k` and horizon `H`, the
   cutoffs are `end - k*H, ..., end - H`, oldest first, so the last fold's test
   window ends exactly at `dataset_end`.
2. For each cutoff, every model is constructed fresh, then fitted and asked to
   predict using **only** observations up to and including the cutoff. It is
   scored on the following `H` days.
3. A series takes part only if it has at least 56 days of history before the
   first cutoff, so every model is scored on the same series in every fold.
4. Errors from all series and folds are pooled into one set of metrics per
   model.

The test `test_backtest_never_shows_future_data_to_models` uses a spy model
to assert that no model ever receives a date after its cutoff.

## Metrics

Error is `forecast - actual`.

| Metric | Definition |
|--------|------------|
| MAE | mean(abs(error)), units per SKU-store-day |
| RMSE | sqrt(mean(error squared)) |
| WAPE | sum(abs(error)) / sum(abs(actual)) |
| Bias | sum(error) / sum(abs(actual)); positive means over-forecasting |

WAPE and bias are reported as `null` (shown as "n/a"), never 0, when actual
demand sums to zero. `tests/ml/test_forecasting_ml.py` checks every metric
against hand-computed values.

## Model selection

Per horizon, models are ranked by WAPE, then MAE. The best **baseline** is the
default choice. LightGBM replaces it **only if it is strictly better**; a tie
keeps the baseline. The comparison endpoint reports the best baseline, the
selected model, and the relative WAPE improvement (0 when a baseline won), so
a model that does not beat the baselines is shown as such.

## Persistence

| Table | Backtest (`params.kind = "backtest"`) | Forecast (`params.kind = "forecast"`) |
|-------|---------------------------------------|----------------------------------------|
| `model_runs` | One row per model, sharing a `group_id`; `metrics` = measured MAE/RMSE/WAPE/bias/n_points; `params` record folds, cutoffs, series count, model hyperparameters, `selected` | One row; references the source backtest run and copies its metrics into `params.backtest_metrics` |
| `forecasts` | Last fold's predictions with `y_true` (actual) for each model | Future predictions (`y_true` null) for `dataset_end + 1 .. + H` |

Only the latest forecast run per horizon is kept. Backtest history is kept for
audit.

## Using it

| Endpoint | Purpose |
|----------|---------|
| `POST /api/v1/models:backtest` `{horizon, folds}` | Run and store a backtest (manager+) |
| `GET /api/v1/models/comparison?horizon=` | Latest stored backtest for a horizon |
| `GET /api/v1/models/runs` | Run history |
| `POST /api/v1/forecasts:generate` `{horizon}` | Forecast all series with the selected model (runs a backtest first if none exists) |
| `GET /api/v1/forecasts`, `/forecasts/series` | Stored forecasts; history plus forecast for one SKU/store |

Supported horizons: 7, 14, 30 and 90 days. A backtest needs at least
`56 + horizon x folds` days of sales history, otherwise it returns `422` with
that requirement. On the 400-day synthetic demo dataset, a 4-model backtest
takes roughly 4-6 seconds and runs inside the request.

## Limitations

- The synthetic demo data is generated (`seed/generate.py`) from a per-series
  linear trend, weekly seasonality, random promotions and noise. Accuracy measured on it says
  nothing about real data; the app labels it "Measured on synthetic demo data".
- No prediction intervals yet: forecasts are point estimates.
- Zero-filled stockout days understate true demand (see Data preparation).
- Training is synchronous. Much larger catalogues would need a background job.
