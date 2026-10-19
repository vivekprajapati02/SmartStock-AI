# Architecture

SmartStock AI backend is a modular FastAPI application backed by PostgreSQL.

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
