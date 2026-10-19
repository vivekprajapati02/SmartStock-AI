# Architecture

SmartStock AI is a modular FastAPI backend on PostgreSQL with a Flutter client
(`mobile/`) for mobile, web and desktop.

## Layering

```
HTTP (FastAPI routers, app/api/v1)
        |
Dependencies (app/api/deps.py: auth + tenant context + RBAC)
        |
Services (app/services: business logic, owns transactions)
        |
ORM (app/models: SQLAlchemy 2.0 typed models)
        |
Database (PostgreSQL, Alembic migrations, RLS)
```

Cross-cutting concerns live in `app/core` (config, logging, errors, security,
rbac) and `app/db` (engine/session, tenant context, RLS helpers).

## Request lifecycle

1. **Request id** middleware assigns/propagates `X-Request-ID` and stores it on
   `request.state`.
2. A route declares dependencies from `app/api/deps.py`.
3. `get_current_user` decodes the access token, reads `org`/`sub` claims, binds
   the session to the organisation, then loads the user (401 on failure).
4. `require_roles(...)` enforces the minimum role (403 on failure).
5. Service functions run the business logic and commit their own transactions.
6. Unexpected exceptions are logged and returned as a generic 500; expected
   errors return the structured envelope.

## Multi-tenancy

Isolation is enforced at two independent layers:

- **Service layer**: every query includes `org_id = <caller org>`.
- **Database layer (RLS)**: each org-scoped table has a policy
  `org_id = NULLIF(current_setting('app.current_org', true), '')::uuid`.
  `app.db.session` applies `set_config('app.current_org', ..., true)` at the
  start of every transaction via an `after_begin` listener, so the context
  survives commits and is cleared automatically between transactions (no leakage
  across pooled connections). Because the value is transaction-local, RLS is
  inherently fail-closed: without a context, the comparison is `NULL` and no
  rows are returned.

`organizations` is the tenant root and is intentionally not org-scoped.

## Transactions

Services own transaction boundaries. Multi-step operations (writing a stock
movement and updating the inventory row, or receiving a purchase order) execute
inside a single transaction so a failure rolls everything back. `tests/integration/test_postgres_transactions.py`
asserts complete rollback after an injected failure.

## CSV import

`app/services/import_service.py` parses the upload with the standard `csv`
module, validates each row with the `SalesRowIn` Pydantic model, resolves SKU
and store against the organisation's catalogue, and checks the natural key
`(org, product, store, sale_date)` against stored history and earlier rows in
the same file. The `import_batches` record and all valid `sales_history` rows
are committed together. If the commit hits the unique constraint (a concurrent
import), everything is rolled back and a `failed` batch is recorded instead, so
an import is never half-applied. Imported sales feed the dashboard demand trend
and, from Phase 5, forecasting.

## Data model

| Table | Purpose |
|-------|---------|
| `organizations` | Tenant root |
| `users` | Users with role + hashed password (unique email per org) |
| `categories`, `suppliers`, `stores` | Reference data |
| `products` | SKUs (unique per org) |
| `inventory` | Current stock per product/store (unique triple) |
| `stock_movements` | Immutable stock-change ledger |
| `sales_history` | Daily sold quantity (unique per org/product/store/date) |
| `model_runs` | Forecasting backtest metadata + measured metrics |
| `forecasts` | Stored predictions (`y_true` nullable) |
| `alerts` | Stock alerts |
| `purchase_orders`, `purchase_order_items` | Procurement with partial receipts |
| `import_batches` | CSV import audit records |

Column types are portable (UUID, Numeric, timezone-aware timestamps) so fast
tests can run on SQLite while production and integration tests use PostgreSQL.

## Security notes

- Passwords are hashed with bcrypt (per-password salt); plaintext is never
  stored and never logged.
- JWTs carry a `type` claim; refresh tokens cannot be replayed as access tokens.
- Authentication failures return a single generic message to avoid leaking which
  credential was wrong.
- Cross-tenant access is prevented at both the service and database layers.

## Flutter client

```
Views (modules/*/..._view.dart, Material 3, responsive)
        |
GetX controllers (modules/*, reactive state; PagedController for lists)
        |
Repositories (data/repositories: auth, catalog, inventory, analytics)
        |
ApiClient (core/network: Dio + AuthInterceptor) -> /api/v1
```

- **DI and routing**: `main.dart` registers config, token storage, cache,
  `ApiClient`, repositories, `SessionService` and `ConnectivityService` as
  permanent GetX services. `routes/app_pages.dart` binds per-screen controllers
  and guards authenticated routes with `AuthMiddleware`. The splash route
  restores a stored session via `/auth/me`.
- **Networking**: one `Dio` instance with `X-Request-ID` and `AuthInterceptor`
  (a `QueuedInterceptor`). On a 401 it refreshes once via `/auth/refresh`;
  concurrent 401s wait behind that single refresh, and refresh/retry use a
  separate interceptor-free `Dio` to avoid recursion and queue deadlocks. A
  failed refresh clears tokens and routes to login. All failures surface as a
  typed `ApiException` parsed from the backend error envelope, including
  per-field validation messages.
- **Data fidelity**: the backend serialises `Decimal` as JSON strings; DTOs parse
  both strings and numbers. Every number on screen comes from an API response.
- **States**: `AsyncStateView` renders loading, error (retry), empty, offline
  and data. The dashboard and first inventory page store the last successful
  response in `shared_preferences` and, only when the server is unreachable,
  show it with an "Offline - showing data saved <time>" banner.
- **RBAC in the UI**: `RoleGate` hides write actions below `manager`; the
  backend remains the source of truth.
- **Configuration**: `API_BASE_URL` via `--dart-define`. Web builds with an
  empty value use same-origin `/api/v1` behind the nginx reverse proxy;
  desktop and mobile call the API directly.
- **Tests**: DTO parsing, error mapping and the refresh interceptor
  (fake Dio adapter), controllers over real repositories with a fake backend,
  widget tests for each main screen, and `test/live` contract tests that run the
  repositories against a running backend.
