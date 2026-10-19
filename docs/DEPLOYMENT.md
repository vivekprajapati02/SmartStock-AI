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

## Notes for later phases

CI/CD (GitHub Actions with a PostgreSQL service) and the Flutter build pipeline
are scheduled for Phase 7 of the plan. Forecasting, CSV import, purchase orders,
and the Flutter client are intentionally out of scope for Phase 2.
