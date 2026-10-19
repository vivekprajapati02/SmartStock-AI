# SmartStock AI

AI-powered inventory and demand forecasting platform.

- **Mobile / Web / Desktop client:** Flutter + GetX + Dio (Phase 3)
- **Backend:** Python + FastAPI + SQLAlchemy + Alembic + PostgreSQL
- **ML:** pandas / NumPy / scikit-learn / LightGBM (Phase 5)

This repository currently contains the **Phase 2 backend foundation**: project
skeleton, full database schema with migrations, multi-tenant isolation, JWT
authentication with role-based access control, synthetic demo data, health
checks, Docker tooling, and tests.

See `docs/IMPLEMENTATION_PLAN.md` for the full phased plan.

## Repository layout

```
backend/
  app/
    api/v1/       # routers (auth, users, health)
    core/         # config, logging, errors, security, rbac
    db/           # base, session (RLS context), rls helpers
    models/       # SQLAlchemy ORM models (org-scoped)
    schemas/      # Pydantic v2 request/response models
    services/     # business logic (transactions live here)
    main.py       # FastAPI application factory
  alembic/        # migrations (initial schema + RLS policies)
  seed/           # reproducible synthetic data generator
  tests/          # unit / api / integration suites
docker-compose.yml
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

This starts PostgreSQL and the API (migrations run automatically on startup) on
http://localhost:8000.

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

## Documentation

- `docs/IMPLEMENTATION_PLAN.md` — phased plan and decisions
- `docs/ARCHITECTURE.md` — backend architecture and data model
- `docs/API.md` — endpoint reference
- `docs/DEPLOYMENT.md` — deployment guidance
