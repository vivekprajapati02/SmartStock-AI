# Deployment

## Container image

`backend/Dockerfile` is a multi-stage build:

- **builder** installs dependencies into `/opt/venv`.
- **runtime** copies the virtualenv and application code, drops to a non-root
  `appuser`, exposes port `8000`, and defines a `curl`-based healthcheck.

The container command runs `alembic upgrade head` before starting Uvicorn so the
schema is always current.

```bash
cd backend
docker build -t smartstock-api .
docker run --rm -p 8000:8000 \
  -e DATABASE_URL=postgresql+psycopg2://user:pass@host:5432/smartstock \
  -e JWT_SECRET_KEY="$(python -c 'import secrets;print(secrets.token_urlsafe(48))')" \
  smartstock-api
```

## Docker Compose (local stack)

```bash
# Start PostgreSQL + API (migrations run automatically)
docker compose up --build

# Generate demo data into the running stack
docker compose exec api python -m seed.generate --slug synthetic-demo --days 400
```

## Required configuration in production

| Variable | Notes |
|----------|-------|
| `DATABASE_URL` | Point at a managed PostgreSQL instance. |
| `JWT_SECRET_KEY` | **Must** be a long random value; never reuse the dev default. |
| `ENVIRONMENT` | Set to `production`. |
| `CORS_ORIGINS` | Restrict to the known frontend origins (do not leave `*`). |
| `ACCESS_TOKEN_EXPIRE_MINUTES` / `REFRESH_TOKEN_EXPIRE_DAYS` | Tune to policy. |

## Migrations

```bash
# Apply to head
alembic upgrade head

# Create a new revision after changing models
alembic revision --autogenerate -m "describe change"

# Roll back one revision
alembic downgrade -1
```

The initial migration also creates the PostgreSQL Row-Level Security policies.
Run migrations with a role that owns the tables; `FORCE ROW LEVEL SECURITY` is
enabled so policies apply even to the table owner.

## Operational checks

- `GET /health` — liveness (no dependencies).
- `GET /health/ready` — readiness (database reachable).

## Web client image

`mobile/Dockerfile` builds the Flutter web app (`flutter build web` with an empty
`API_BASE_URL`, i.e. same-origin requests) and serves it from `nginx:alpine`.
`mobile/nginx.conf` serves the app shell with an `index.html` fallback and
reverse-proxies `/api/` and `/health` to `${API_UPSTREAM}` (default
`http://api:8000`), so the browser talks to a single origin and no CORS is
needed.

```bash
docker compose up --build        # web on http://localhost:8080, API on :8000
```

For a standalone deployment, set `API_UPSTREAM` to the backend's internal URL.
Desktop and mobile builds do not use the proxy; build them with
`--dart-define=API_BASE_URL=https://api.example.com` and add that client origin
to `CORS_ORIGINS` only if it is a browser.

## Database role (required for tenant isolation)

PostgreSQL superusers, and roles with `BYPASSRLS`, ignore row-level security
even when tables use `FORCE ROW LEVEL SECURITY`. The API must therefore
connect as an ordinary role that owns the application database:

```sql
CREATE ROLE smartstock LOGIN PASSWORD '...' NOSUPERUSER NOBYPASSRLS;
CREATE DATABASE smartstock OWNER smartstock;
```

`docker-compose.yml` does this through `backend/docker/initdb/01-app-role.sql`,
which the official image runs on first start; the `postgres` superuser is only
for maintenance. Init scripts run only on an **empty** volume, so recreate an
older volume once with `docker compose down -v` (this deletes its data).

## Continuous integration

`.github/workflows/ci.yml` runs on pushes to `main` and on pull requests:

| Job | Steps |
|-----|-------|
| Backend (Python 3.11 and 3.14) | PostgreSQL 15 service with a non-superuser app role; `ruff check`; `pytest` including the PostgreSQL RLS, transaction and workflow integration tests; `alembic upgrade head` plus a seed smoke test |
| Flutter | `flutter analyze`, `flutter test`, `flutter build web` (Flutter 3.47.4) |
| Docker images | Builds the API and web images (no push), after both test jobs pass |

## Resource notes

Backtests and forecast generation train models inside the request: about 4-6
seconds for the 30-series demo dataset. The Flutter client allows up to 3
minutes for these calls. Much larger catalogues would need a background
worker.
