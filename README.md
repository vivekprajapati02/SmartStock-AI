# SmartStock AI

[![CI](https://github.com/vivekprajapati02/SmartStock-AI/actions/workflows/ci.yml/badge.svg)](https://github.com/vivekprajapati02/SmartStock-AI/actions/workflows/ci.yml)

AI-powered inventory and demand forecasting platform.

- **Mobile / Web / Desktop client:** Flutter + GetX + Dio
- **Backend:** Python + FastAPI + SQLAlchemy + Alembic + PostgreSQL
- **ML:** pandas / NumPy / scikit-learn / LightGBM (see `docs/ML.md`)

All seven phases of `docs/IMPLEMENTATION_PLAN.md` are implemented: the backend foundation
(schema, auth/RBAC, tenant isolation, synthetic demo data, Docker tooling) plus
catalogue, inventory-movement and dashboard APIs, the Flutter client with
Auth, Dashboard, Inventory, Movements and Catalogue screens on those real APIs,
(Phase 4) sales-history CSV import with validation, duplicate detection and
per-row error reports, and (Phase 5) demand forecasting with baselines and
LightGBM evaluated by chronological backtesting, and (Phase 6) replenishment
recommendations, rule-based stock alerts and purchase orders with
transactional partial receipts.

See `docs/IMPLEMENTATION_PLAN.md` for the full phased plan.

## Repository layout

```
backend/
  app/
    api/v1/       # routers (auth, users, catalog, products, inventory, analytics)
    core/         # config, logging, errors, security, rbac
    db/           # base, session (RLS context), rls helpers
    models/       # SQLAlchemy ORM models (org-scoped)
    schemas/      # Pydantic v2 request/response models
    services/     # business logic (transactions live here)
    main.py       # FastAPI application factory
  alembic/        # migrations (initial schema + RLS policies)
  seed/           # reproducible synthetic data generator
  tests/          # unit / api / integration suites
mobile/           # Flutter client (Android, iOS, web, Windows, macOS, Linux)
  lib/
    core/         # config, Dio client + auth interceptor, storage, paging, theme
    data/         # DTO models + repositories (one per API area)
    modules/      # GetX controllers + views: auth, shell, dashboard,
                  # inventory, movements, catalog
    routes/       # GetX routes, bindings, auth middleware
    widgets/      # shared loading/error/empty/offline view, KPI cards, lists
  test/           # unit, controller, widget and live API contract tests
  Dockerfile      # web build served by nginx with /api reverse proxy
docker-compose.yml   # postgres (non-superuser app role) + api + web
.github/workflows/ci.yml
docs/
```

## Quickstart (local, without Docker)

Prerequisites: Python 3.11+, PostgreSQL 15+.

```bash
# 1. Create the databases and user (example psql commands)
createuser smartstock --pwprompt
createdb -O smartstock smartstock
createdb -O smartstock smartstock_test

# 2. Create a virtualenv and install dependencies
cd backend
python -m venv .venv
.venv/bin/pip install -e ".[dev]"

# 3. Configure environment
cp .env.example .env

# 4. Apply migrations
.venv/bin/alembic upgrade head

# 5. Generate synthetic demo data (reproducible, idempotent)
.venv/bin/python -m seed.generate --slug synthetic-demo --days 400

# 6. Run the API
.venv/bin/uvicorn app.main:app --reload
```

The API is then available at http://localhost:8000 with interactive docs at
`/docs` and the OpenAPI schema at `/openapi.json`.

## Quickstart (Docker)

```bash
docker compose up --build
```

This starts PostgreSQL (the API connects as a non-superuser role so row-level
security applies; see `docs/DEPLOYMENT.md`), the API (migrations run automatically on startup) on
http://localhost:8000, and the Flutter web client on http://localhost:8080.
nginx in the web container proxies `/api` and `/health` to the API, so the
browser uses a single origin.

## Flutter client

Prerequisites: Flutter 3.47+ (Dart 3.13+). The backend must be running and,
for demo data, seeded (see above).

```bash
cd mobile
flutter pub get

# Web (Chrome) against a local backend
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000

# Desktop / mobile call the API base URL directly
flutter run -d windows --dart-define=API_BASE_URL=http://localhost:8000
flutter run -d <android-device> --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`API_BASE_URL` is the backend origin (no `/api/v1`). On web, leaving it empty
makes requests same-origin (`/api/v1/...`), which is how the Docker web image
works behind its reverse proxy. Off web it defaults to `http://localhost:8000`.

Demo login after seeding: organisation `synthetic-demo`, email
`owner@synthetic-demo.com`, password `demo-password-123`. The dashboard shows a
"Synthetic demo data" badge for that organisation; a newly registered
organisation starts with zeros.

Screens: sign in / register, Dashboard (KPIs + daily demand chart, 7/30/90
days), Inventory (search, store and low-stock filters, detail with
replenishment settings), Movements (ledger + record in/out/adjust), Catalogue
(products, stores, categories, suppliers), Imports (upload a sales CSV, see
history and a per-line problem report), Forecasts (actual sales and the stored
forecast for any SKU/store), Model evaluation (stored backtest metrics per
model, which model was selected and why, forecast vs actual), Alerts (check
stock now; acknowledge/resolve/dismiss), Replenishment (recommended order
quantities with every input shown; save as stock settings; draft purchase
orders per supplier), Purchase orders (create, submit, approve, receive
deliveries partially). Write actions are only shown to
`manager` and above, and purchase-order approval only to `admin`/`owner`;
the backend enforces the same rules. Access tokens are
refreshed automatically on a 401. When the server is unreachable, the last
successfully loaded dashboard and first inventory page are shown with an
"Offline - showing data saved ..." banner; nothing is invented.

## Environment variables

| Variable | Description | Default |
|----------|-------------|---------|
| `APP_NAME` | Application name | `SmartStock AI` |
| `ENVIRONMENT` | `development` / `test` / `staging` / `production` | `development` |
| `DEBUG` | Enable debug behaviour | `false` |
| `LOG_LEVEL` | Root log level | `INFO` |
| `DATABASE_URL` | SQLAlchemy database URL | local Postgres |
| `TEST_DATABASE_URL` | Database for PostgreSQL integration tests | local Postgres test DB |
| `JWT_SECRET_KEY` | HMAC signing key for JWTs (**must** be set in production) | dev placeholder |
| `JWT_ALGORITHM` | JWT signing algorithm | `HS256` |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | Access-token lifetime | `30` |
| `REFRESH_TOKEN_EXPIRE_DAYS` | Refresh-token lifetime | `7` |
| `CORS_ORIGINS` | Comma-separated allowed origins or `*` | `*` |

Secrets are never committed. Copy `.env.example` to `.env` and fill in real
values. Generate a key with:

```bash
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

## API overview (v1)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Liveness probe |
| `GET` | `/health/ready` | Readiness probe (checks the database) |
| `POST` | `/api/v1/auth/register` | Create an organisation and its owner user |
| `POST` | `/api/v1/auth/login` | Exchange credentials for tokens |
| `POST` | `/api/v1/auth/refresh` | Exchange a refresh token for a new token pair |
| `GET` | `/api/v1/auth/me` | Current authenticated user |
| `GET` | `/api/v1/users` | List users in the caller's organisation (admin/owner) |
| `POST` | `/api/v1/users` | Create a user in the caller's organisation (admin/owner) |
| `GET/POST/PATCH/DELETE` | `/api/v1/categories` | Category CRUD |
| `GET/POST/PATCH/DELETE` | `/api/v1/suppliers` | Supplier CRUD |
| `GET/POST/PATCH/DELETE` | `/api/v1/stores` | Store CRUD |
| `GET/POST/PATCH` | `/api/v1/products` | Product CRUD (SKU unique per org) |
| `GET/PATCH` | `/api/v1/inventory` | Inventory list/get/settings |
| `GET/POST` | `/api/v1/movements` | Stock movements (transactional) |
| `GET` | `/api/v1/analytics/dashboard` | Dashboard metrics from stored data |
| `POST` | `/api/v1/imports` | Upload a sales CSV (multipart); returns the batch report |
| `GET` | `/api/v1/imports`, `/api/v1/imports/{id}` | Import history and per-row errors |
| `GET` | `/api/v1/imports/template` | CSV header + example row from your catalogue |
| `POST` | `/api/v1/models:backtest` | Chronological backtest of all models (stored) |
| `GET` | `/api/v1/models/comparison`, `/api/v1/models/runs` | Stored backtest metrics and run history |
| `POST` | `/api/v1/forecasts:generate` | Forecast every SKU/store with the selected model |
| `GET` | `/api/v1/forecasts`, `/api/v1/forecasts/series` | Stored forecasts; history + forecast for one SKU/store |
| `GET/POST` | `/api/v1/replenishment`, `/api/v1/replenishment/apply` | Reorder point, safety stock, target, recommended qty |
| `GET/POST/PATCH` | `/api/v1/alerts`, `/api/v1/alerts:evaluate`, `/api/v1/alerts/{id}` | Low stock, stockout risk, overstock, slow moving |
| `GET/POST/PATCH` | `/api/v1/purchase-orders[...]` | Draft, submit, approve (admin+), cancel, partial receive |

All errors share one envelope:

```json
{
  "error": {
    "code": "not_found",
    "message": "Resource not found.",
    "details": [],
    "request_id": "..."
  }
}
```

## Roles

Roles are ordered: `owner` > `admin` > `manager` > `viewer`. A higher role
implicitly satisfies any requirement of a lower role.

## Data isolation

Every domain table carries `org_id`. Isolation is enforced twice:

1. **Service layer** — all queries filter by the caller's `org_id`.
2. **Database layer** — PostgreSQL Row-Level Security policies restrict rows to
   the transaction-local `app.current_org` setting. The setting is applied per
   transaction; an unset context returns **no rows** (fail closed).

## Reproducible synthetic data

`seed/generate.py` creates a clearly-labelled demo organisation (`is_demo=true`,
`DEMO-` SKU prefix) with categories, suppliers, stores, products, inventory,
stock movements, and at least 12 months of daily sales. Output is a pure
function of `--seed`, and re-running never duplicates rows.

```bash
.venv/bin/python -m seed.generate --slug synthetic-demo --days 400 --products 15 --stores 2 --seed 42
```

## Testing

```bash
cd backend

# Fast tests (SQLite only)
.venv/bin/python -m pytest -m "not postgres"

# Everything, including PostgreSQL integration tests (RLS, transactions)
TEST_DATABASE_URL=postgresql+psycopg2://smartstock:smartstock@localhost:5432/smartstock_test \
  .venv/bin/python -m pytest

# Lint
.venv/bin/ruff check app seed tests
```

The PostgreSQL integration tests must connect as a **non-superuser** role
(superusers bypass row-level security). `createuser` without `-s` creates one.
CI (`.github/workflows/ci.yml`) runs lint and the full suite, including
PostgreSQL, on Python 3.11 and 3.14, then Flutter analyze/test/web build and
both Docker image builds.

Flutter:

```bash
cd mobile
flutter analyze
flutter test                      # unit, controller and widget tests

# Live contract tests: the app's repositories against a running, seeded backend
LIVE_API_URL=http://localhost:8000 flutter test test/live
```

## Documentation

- `docs/IMPLEMENTATION_PLAN.md` — phased plan, decisions and delivery status
- `docs/ARCHITECTURE.md` — backend architecture and data model
- `docs/API.md` — endpoint reference
- `docs/ML.md` — forecasting models, backtesting, metrics and limitations
- `docs/DEPLOYMENT.md` — deployment guidance
