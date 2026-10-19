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
trend. Empty organisations return zeros, not placeholders. `is_demo` is true
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
