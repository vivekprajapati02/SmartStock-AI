# API Reference (v1)

Base URL: `/api/v1`. Interactive docs: `/docs`. OpenAPI: `/openapi.json`.

## Error envelope

Every error response has the same shape:

```json
{
  "error": {
    "code": "validation_error",
    "message": "The request payload failed validation.",
    "details": [{"field": "email", "message": "value is not a valid email address", "type": "value_error"}],
    "request_id": "8f1c..."
  }
}
```

Common codes: `validation_error` (422), `unauthenticated` (401),
`permission_denied` (403), `not_found` (404), `conflict` (409),
`internal_error` (500).

## Health

### `GET /health`
Liveness probe.

```json
{ "status": "ok", "app": "SmartStock AI", "environment": "development" }
```

### `GET /health/ready`
Readiness probe; verifies database connectivity.

```json
{ "status": "ready", "database": "ok" }
```

## Authentication

### `POST /api/v1/auth/register`
Creates a new organisation and its `owner` user in one transaction.

Request:
```json
{
  "organization_name": "Acme Corp",
  "organization_slug": "acme-corp",
  "email": "owner@acme-corp.com",
  "password": "password-123",
  "full_name": "Owner"
}
```

Response `201`:
```json
{
  "user": { "id": "...", "org_id": "...", "email": "owner@acme-corp.com", "role": "owner", "is_active": true, "created_at": "..." },
  "tokens": { "access_token": "...", "refresh_token": "...", "token_type": "bearer", "expires_in": 1800 }
}
```

Errors: `409` if the organisation name/slug already exists; `422` for invalid
email or weak password (min 8 characters, max 72 bytes UTF-8).

### `POST /api/v1/auth/login`
Request:
```json
{ "organization": "acme-corp", "email": "owner@acme-corp.com", "password": "password-123" }
```
Response `200` with the same shape as register. `401` on any mismatch.

### `POST /api/v1/auth/refresh`
Request:
```json
{ "refresh_token": "..." }
```
Response `200` with the same `{user, tokens}` shape as login (a fresh access
and refresh token pair under `tokens`). `401` if the token is expired, invalid,
or is not a refresh token.

### `GET /api/v1/auth/me`
Requires `Authorization: Bearer <access_token>`. Returns the current user.

## Users

Requires role `admin` or `owner`.

### `GET /api/v1/users?limit=50&offset=0`
Returns a page of users in the caller's organisation.

```json
{ "items": [ { "id": "...", "email": "...", "role": "viewer" } ], "total": 1, "limit": 50, "offset": 0 }
```

### `POST /api/v1/users`
Request:
```json
{ "email": "manager@acme-corp.com", "password": "password-123", "full_name": "Manager", "role": "manager" }
```
Response `201` with the created user. `409` if the email already exists in the
organisation.

## Authorization model

| Role | Rank |
|------|------|
| `viewer` | 1 |
| `manager` | 2 |
| `admin` | 3 |
| `owner` | 4 |

An endpoint requiring role R accepts any role with rank ≥ R.

## Catalogue

Authenticated. Create/update/delete require `manager` or above.

- `GET/POST /api/v1/categories` and `GET/PATCH/DELETE /api/v1/categories/{id}`
- `GET/POST /api/v1/suppliers` and `GET/PATCH/DELETE /api/v1/suppliers/{id}`
- `GET/POST /api/v1/stores` and `GET/PATCH/DELETE /api/v1/stores/{id}`
- `GET/POST /api/v1/products` and `GET/PATCH /api/v1/products/{id}`

Creating a product (or store) also creates zero-quantity inventory rows for
every store/product pair. Duplicate names/SKUs in the same org return `409`.
Cross-org access returns `404`.

## Inventory

- `GET /api/v1/inventory` — list current stock (filters: `store_id`, `low_stock`, `search`)
- `GET /api/v1/inventory/{id}`
- `PATCH /api/v1/inventory/{id}` — update reorder point / safety stock / lead time
- `POST /api/v1/movements` — record `in` / `out` / `adjust` and update quantity
  on hand in one transaction. Outbound that would go negative returns `422` and
  does not change stock.
- `GET /api/v1/movements` — movement ledger

## Analytics

### `GET /api/v1/analytics/dashboard?trend_days=30`

All numbers are computed from stored data: inventory value, SKU/store counts,
low-stock and stockout counts, pending purchase-order count, and a daily demand
trend, plus `open_alert_count`. Empty organisations return zeros, not
placeholders. `is_demo` is true
only when the organisation was created by the seed script.

## Imports (sales history CSV)

Uploading requires `manager` or above; reading requires any role.

### `POST /api/v1/imports`
`multipart/form-data` with one field `file`. Columns (header names are
case-insensitive, order does not matter, extra columns are ignored):

| Column | Rules |
|--------|-------|
| `sku` | Must match an existing product SKU in the organisation (exact match) |
| `store` | Must match an existing store name (case-insensitive) |
| `sale_date` | ISO `YYYY-MM-DD`, not in the future |
| `quantity` | Number >= 0, at most 3 decimal places |

Limits: 5 MB, 50,000 data rows, UTF-8 (a BOM is accepted). Blank lines are
skipped.

The natural key is `(org, product, store, sale_date)`. A row whose key already
exists in stored sales history, or appeared earlier in the same file, is a
**duplicate**: it is reported and the stored value is not changed. Every upload
records a batch (response `201`) and the batch's valid rows are inserted in the
same transaction - all of them or none.

| `status` | Meaning |
|----------|---------|
| `completed` | Every row was imported |
| `partial` | Some rows imported; others invalid or duplicate |
| `failed` | Nothing imported (file-level problem, or no valid rows) |

```json
{
  "id": "...", "filename": "sales.csv", "status": "partial",
  "total_rows": 4, "valid_rows": 2, "invalid_rows": 1, "duplicate_rows": 1,
  "error_count": 2, "errors_truncated": false, "created_at": "...",
  "errors": [
    {"row": 3, "column": "sku", "value": "NOPE", "message": "Unknown SKU for this organisation.", "kind": "invalid"},
    {"row": 4, "column": "sale_date", "value": "2026-10-18", "message": "Same SKU, store and date as row 2 in this file.", "kind": "duplicate"}
  ]
}
```

`row` is the 1-based data row (file line = `row + 1`). File-level problems
(missing columns, not UTF-8, empty, too large) have `row: null` and
`kind: "file"`. Counts are always exact; the stored `errors` list is capped at
1,000 entries and `errors_truncated` says when more exist.

### `GET /api/v1/imports?limit=50&offset=0`
Import history, newest first, without the `errors` list.

### `GET /api/v1/imports/{id}`
One batch including its error report. Another organisation's batch returns `404`.

### `GET /api/v1/imports/template`
`text/csv` header plus one example row using the organisation's own first SKU
and store with quantity `0` (header only when the catalogue is empty).

## Forecasting and model evaluation

See `docs/ML.md` for models, backtesting and metric definitions. Horizons:
`7`, `14`, `30`, `90` (anything else is `422`). Running a backtest or
generating forecasts requires `manager`+; reading requires any role.

### `POST /api/v1/models:backtest`
Request `{"horizon": 30, "folds": 3}` (folds 1-6). Trains and scores every
model chronologically, stores the results, and returns the comparison below.
`422` when there is no sales history or too little for the horizon x folds.

### `GET /api/v1/models/comparison?horizon=30`
Latest stored backtest for the horizon (field values below only illustrate
the shape; real responses carry measured numbers):

```json
{
  "horizon": 30, "group_id": "...", "run_at": "...", "folds": 3,
  "dataset_start": "2025-09-15", "dataset_end": "2026-10-19",
  "cutoffs": ["2026-07-21", "2026-08-20", "2026-09-19"], "n_series": 30,
  "models": [
    {"id": "...", "model_name": "lightgbm", "kind": "backtest", "selected": true, "is_baseline": false,
     "metrics": {"mae": 0.0, "rmse": 0.0, "wape": 0.0, "bias": 0.0, "n_points": 2700}, "params": {}}
  ],
  "selected_model": "lightgbm", "best_baseline": "moving_average",
  "wape_improvement_vs_baseline": 0.0,
  "forecast_vs_actual": [{"day": "2026-09-20", "actual": 0.0, "predicted": 0.0}],
  "is_demo": true
}
```

`models` is sorted best-first by WAPE. With no backtest yet, `models` is `[]`
and `selected_model` is `null`. `forecast_vs_actual` is the selected model's
last fold summed over all series per day.

### `GET /api/v1/models/runs?horizon=&kind=backtest|forecast&limit=&offset=`
Paginated run history, newest first.

### `POST /api/v1/forecasts:generate`
Request `{"horizon": 30}`. Uses the model selected by the latest backtest for
the horizon (running one first if none exists), refits it on all history and
stores forecasts for `dataset_end + 1 ... dataset_end + horizon` for every
SKU/store with at least 56 days of history. It replaces the previous forecast
run for that horizon and returns the first page of `GET /forecasts`.

### `GET /api/v1/forecasts?horizon=&product_id=&store_id=&limit=&offset=`
Points from the latest forecast run: `{"run": {...} | null, "items": [{"product_id", "store_id", "sku", "product_name", "store_name", "forecast_date", "quantity"}], "total", "limit", "offset"}`.

### `GET /api/v1/forecasts/series?product_id=&store_id=&horizon=&history_days=60`
Recent actual daily sales (zero-filled) plus the stored forecast for one
SKU/store: `{"run", "history": [{"day", "quantity"}], "forecast": [...]}`.
Another organisation's product or store returns `404`.

## Replenishment

### `GET /api/v1/replenishment?store_id=&needs_reorder=&service_level=0.95&review_days=7&limit=&offset=`
One row per SKU/store, items needing reorder first. Every input is returned so
the recommendation can be traced:

| Field | Meaning |
|-------|---------|
| `avg_daily_demand`, `demand_std` | From the last 56 days of stored sales (zero-filled); mean is replaced by the stored forecast when one covers lead time + review |
| `demand_source` | `forecast` (with `forecast_model`), `history`, or `none` (no sales data at all) |
| `safety_stock` | z(service level) x demand_std x sqrt(lead_time_days) |
| `lead_time_demand`, `reorder_point` | Demand over the lead time; reorder point = that + safety stock |
| `target_stock` | Demand over lead time + review period + safety stock |
| `on_order`, `inventory_position` | Open (pending/approved/partial) PO quantities not yet received; position = on hand + on order |
| `recommended_qty` | ceil(target - position) when position <= reorder point, else 0 |
| `current_reorder_point`, `current_safety_stock` | The values saved on the inventory row |

The list response also carries `service_level`, `z_score`, `review_days`,
`history_days` and `history_end`.

### `POST /api/v1/replenishment/apply` (manager+)
`{"store_id"?: "...", "inventory_ids"?: [...], "service_level"?: 0.95, "review_days"?: 7}`
saves the computed reorder point and safety stock onto the inventory rows,
returning `{"updated": n}`.

## Alerts

### `POST /api/v1/alerts:evaluate` (manager+)
Checks every SKU/store and returns `{"created", "updated", "resolved", "open_total", "evaluated_items"}`.

| Type | Condition | Severity |
|------|-----------|----------|
| `low_stock` | 0 < on hand <= saved reorder point | `high` if on hand <= saved safety stock, else `medium` |
| `stockout_risk` | demand > 0 and on hand + on order < lead-time demand | `critical` if on hand is 0, else `high` |
| `overstock` | demand > 0 and days of cover > max(60, 3 x (lead + review)) | `medium` if more than twice that, else `low` |
| `slow_moving` | on hand > 0, no sales in the last 30 days while the organisation has recent sales | `low` |

There is one non-resolved alert per (product, store, type). Open and
acknowledged alerts are updated while their condition holds and resolved
automatically when it clears. Dismissed alerts are not re-opened while their
condition persists.

### `GET /api/v1/alerts?status=&alert_type=&severity=&store_id=&limit=&offset=`
Most severe first, then newest.

### `PATCH /api/v1/alerts/{id}` (manager+)
`{"status": "acknowledged" | "resolved" | "dismissed"}`.

## Purchase orders

Lifecycle: `draft` -> (`submit`) `pending` -> (`approve`, **admin/owner only**)
`approved` -> (`receive`) `partial` -> `received`. `cancel` is allowed from
`draft`, `pending` and `approved`. An action from any other status returns
`409`.

| Endpoint | Notes |
|----------|-------|
| `POST /api/v1/purchase-orders` | `{"supplier_id", "store_id", "reference"?, "expected_date"?, "items": [{"product_id", "quantity_ordered"}]}`; each product at most once; quantities > 0 |
| `GET /api/v1/purchase-orders?status=&supplier_id=&store_id=` | Summaries with `line_count`, `total_ordered`, `total_received`, `estimated_cost` (ordered x current unit cost) |
| `GET /api/v1/purchase-orders/{id}` | Includes `items` with `quantity_remaining` |
| `PATCH /api/v1/purchase-orders/{id}` | Draft only; `items` replaces all lines |
| `POST /api/v1/purchase-orders/{id}/submit` \| `approve` \| `cancel` | Status transitions |
| `POST /api/v1/purchase-orders/{id}/receive` | `{"lines": [{"item_id", "quantity"}], "note"?}` |
| `POST /api/v1/purchase-orders/from-recommendations` | `{"store_id"}` -> one draft per supplier for the store's `recommended_qty`; products without a supplier are listed in `skipped` |

A receipt writes one `in` stock movement per line (reference = the PO
reference or `PO-<id prefix>`), increases on-hand stock, and updates line and
order status, all in a single transaction. If any line is invalid (not on
this order, or more than the remaining quantity), the whole receipt is
rejected with `422` and nothing changes.
