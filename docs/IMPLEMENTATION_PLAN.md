# SmartStock AI - Implementation Plan

Status: **Phase 1 (planning) - awaiting review**
Author: AI Coding Agent
Last updated: 2026-10-15

---

## 1. Repository Inspection Findings

| Item | Finding |
|------|---------|
| Repository state | Greenfield. Only `README.md` (1 line) exists. Git initialized, clean tree. |
| Branch / remote | `main`, remote `origin` -> `https://github.com/vivekprajapati02/SmartStock-AI` |
| Submodules | None (`.gitmodules` absent). |
| Python | 3.11.2, pip 23.0.1 available. No target libraries installed. |
| Flutter / Dart | **Not installed** in this environment. |
| PostgreSQL | **Not installed** (no server binaries, no client). |
| Docker | **Not installed** in this environment. |
| Node.js | v22.22.0 (available; not required by the chosen stack). |

Because Flutter, PostgreSQL, and Docker are not present, the plan must separate
**authoring** from **execution**:

- Backend Python code and tests can be authored AND executed locally (once pip deps are installed).
- PostgreSQL and Docker artifacts can be authored, but fully executing them requires either installing PostgreSQL locally or a container runtime.
- Flutter code and widget tests can be authored, but cannot be compiled/run until a Dart/Flutter toolchain is available (locally or via CI).

These constraints are called out again in Section 11 (Open Questions).

---

## 2. Goals and Non-Goals

**Goals**
- Production-ready, modular AI inventory + demand forecasting system.
- Real persistence; every dashboard/analytics number derived from stored data.
- Honest ML: measured via chronological backtesting with MAE / RMSE / WAPE / bias. No fabricated accuracy.
- Multi-tenant data isolation, auth + RBAC, transactional inventory updates.
- Reproducible synthetic demo data.

**Explicit non-goals (per requirements)**
- No microservices, Kafka, Kubernetes, or LLM agents.
- No fabricated metrics or business results.
- No hardcoded dashboard values.

---

## 3. Proposed Repository Layout (monorepo)

```
SmartStock-AI/
  backend/
    app/
      main.py                 # FastAPI app factory, router registration
      core/                   # config, security, deps, exceptions, logging
      db/                     # engine/session, base, seed entrypoints
      models/                 # SQLAlchemy ORM models (org-scoped)
      schemas/                # Pydantic v2 request/response models
      api/v1/                 # routers: auth, products, inventory, imports,
                              #          forecasts, models, alerts,
                              #          replenishment, purchase_orders, analytics
      services/               # business logic (transactions live here)
      ml/                     # features, models, backtesting, metrics
      utils/
    alembic/                  # migrations
    seed/                     # reproducible synthetic data generator
    tests/
      conftest.py
      unit/ integration/ api/ ml/
    pyproject.toml            # deps + tooling (ruff, pytest)
    Dockerfile
    .env.example
  mobile/                     # Flutter app
    lib/
      core/                   # dio client, storage, theme, constants, errors
      data/                   # dto models, datasources, repositories
      modules/                # GetX controllers + views per feature
      routes/                 # GetX routing
      widgets/                # reusable UI (state views, cards, charts)
    test/
  docker-compose.yml          # api + postgres
  .github/workflows/ci.yml
  docs/
    IMPLEMENTATION_PLAN.md    # this file
    ARCHITECTURE.md
    API.md
    ML.md
    DEPLOYMENT.md
  README.md
```

Rationale: single repo keeps schema, API, and client in lockstep; modular backend
directories map 1:1 to features; no premature service split.

---

## 4. Database Schema (PostgreSQL)

All domain tables carry `org_id` (FK -> organizations) for tenant isolation.
Timestamps use `created_at` / `updated_at`; numeric money/quantity use
`Numeric` with fixed precision. Portable column types are preferred so fast unit
tests can run on SQLite when needed.

| Table | Key columns | Notes |
|-------|-------------|-------|
| `organizations` | id, name, created_at | Tenant root. |
| `users` | id, org_id, email (unique per org), hashed_password, role, is_active | Roles: owner, admin, manager, viewer. |
| `categories` | id, org_id, name | |
| `suppliers` | id, org_id, name, contact, lead_time_days | |
| `stores` | id, org_id, name, location | Multi-store. |
| `products` | id, org_id, sku (unique per org), name, category_id, supplier_id, unit, unit_cost, unit_price, is_active | |
| `inventory` | id, org_id, product_id, store_id, quantity_on_hand, reorder_point, safety_stock, lead_time_days, updated_at | Unique (org, product, store). |
| `stock_movements` | id, org_id, product_id, store_id, movement_type (in/out/adjust), quantity, reference, occurred_at, note | Audit trail; source of truth. |
| `sales_history` | id, org_id, product_id, store_id, sale_date, quantity | Forecast input. Unique (org, product, store, date). |
| `model_runs` | id, org_id, model_name, params (JSON), horizon, trained_at, metrics (JSON), dataset_start/end | Backtest metadata. |
| `forecasts` | id, org_id, model_run_id, product_id, store_id, forecast_date, horizon, y_true (nullable), y_pred | Stored predictions. |
| `alerts` | id, org_id, product_id, store_id, alert_type (low_stock/stockout_risk/overstock/slow_moving), severity, status, message, created_at | |
| `purchase_orders` | id, org_id, supplier_id, store_id, status (draft/pending/approved/partial/received/cancelled), created_by, approved_by, expected_date | |
| `purchase_order_items` | id, purchase_order_id, product_id, quantity_ordered, quantity_received | Enables partial receipt. |
| `import_batches` | id, org_id, filename, status, total_rows, valid_rows, invalid_rows, duplicate_rows, errors (JSON), created_at | CSV import audit. |

**Migrations**: Alembic, one revision per schema change; initial revision creates
all tables and indexes (org_id, product/store composite indexes, unique
constraints).

---

## 5. Backend Architecture

### 5.1 Auth & RBAC
- JWT (access + refresh), password hashing via bcrypt/argon2.
- Registration creates an organization + owner user atomically.
- `org_id` and `role` embedded in JWT claims; a FastAPI dependency resolves the
  current user and a second dependency yields an org-scoped session context.
- Role gate decorator/dependency enforces minimum role per endpoint
  (e.g., only admin/owner can approve purchase orders, manage users).
- Every query is filtered by the caller's `org_id`; cross-tenant access returns 404 (not 403) to avoid existence leaks.

### 5.2 Multi-tenancy (DECIDED: org_id filtering + Postgres RLS)
- Shared schema with mandatory `org_id` filter at the repository/service layer
  (single choke point, not per-endpoint ad hoc).
- Defense-in-depth: PostgreSQL Row-Level Security keyed on a session
  `app.current_org` variable. RLS policies are created in the Alembic migration
  and the session variable is set per request. Because RLS is Postgres-specific,
  the SQLite fast-test path relies on the service-layer `org_id` filter, and RLS
  itself is covered by the Postgres integration tests.

### 5.3 Transactions
- Services own transactions. Inventory mutations (movements, PO receipt,
  CSV-driven stock adjustments) run inside a single `session.begin()` block that
  writes the movement, updates `inventory`, and updates PO status atomically.
- On failure, full rollback; no partial stock changes.

### 5.4 API surface (v1, `/api/v1`)
- `auth`: register, login, refresh, me.
- `products` / `categories` / `suppliers` / `stores`: CRUD with pagination.
- `inventory`: list with filters, get, `POST /movements` (adjust/in/out).
- `imports`: `POST /imports` (multipart CSV), `GET /imports`, `GET /imports/{id}` (incl. error report).
- `forecasts`: `POST /forecasts:generate` (horizons 7/14/30/90), `GET /forecasts`.
- `models`: `POST /models:backtest`, `GET /models/runs`, `GET /models/comparison`.
- `alerts`: list/filter, `PATCH /alerts/{id}` (acknowledge/resolve).
- `replenishment`: `GET /replenishment` (reorder point, safety stock, target, recommended qty).
- `purchase-orders`: create, list, get, `POST /{id}/approve`, `POST /{id}/receive` (partial).
- `analytics`: `GET /analytics/dashboard`, `GET /analytics/forecast-vs-actual`.

Responses follow a consistent envelope; errors use structured problem details.

### 5.5 Dashboard (real data only)
`/analytics/dashboard` computes from stored data: total inventory value,
low-stock count, stockout-risk count, demand trend series, pending PO count.
No hardcoded numbers.

---

## 6. ML / Forecasting Design

- **Input**: `sales_history` aggregated per SKU-store into the target frequency
  (daily, or weekly for slow movers), with configurable history window.
- **Features** (for ML/boosting model): lag features, rolling mean/std over
  several windows, day-of-week / month, trend index, optional promo flag.
- **Models**:
  - Baselines: seasonal naive, moving average.
  - Statistical: exponential smoothing.
  - ML: LightGBM regressor (only if it demonstrates value in backtest).
- **Backtesting**: strict chronological, rolling/expanding origin; no shuffling,
  no look-ahead. Train on past, evaluate on future windows.
- **Metrics** (implemented and unit-tested against hand-computed values):
  - MAE, RMSE, WAPE (sum|err| / sum|actual|), Forecast Bias (sum(err)/sum(actual)).
- **Model selection**: per horizon, choose model with best backtest metric;
  results persisted to `model_runs`. Forecasts persisted to `forecasts`.
- **Honesty guarantees**: analytics endpoints read persisted metrics only; if a
  model underperforms a baseline, that is reported as-is. Synthetic data is
  clearly labeled as synthetic.

---

## 7. CSV Import & Validation

- Endpoint accepts multipart CSV; validated row-by-row with Pydantic.
- Checks: required columns, types, non-negative quantities, known SKU/store,
  valid date; **duplicate detection** via natural key
  `(org, product, store, sale_date)`.
- Produces an `import_batches` record with counts and an errors JSON report
  (row number + reason). Valid rows are inserted transactionally; invalid rows
  are reported, not silently dropped.

---

## 8. Alerts, Replenishment, Purchase Orders

- **Alerts**: derived rules over current stock, forecast demand, and velocity:
  low stock (<= reorder point), stockout risk (projected stock <= 0 within lead
  time), overstock (excess vs target), slow-moving (low/no sales over window).
- **Replenishment**: reorder point = demand during lead time + safety stock;
  safety stock = z * stddev(demand) * sqrt(lead_time); target stock and
  recommended order quantity computed per SKU-store.
- **Purchase orders**: draft -> pending -> approved -> (partial) -> received;
  receiving a PO writes stock movements + inventory updates in one transaction
  and supports partial deliveries (per-item `quantity_received`).

---

## 9. Flutter Application

- **State**: GetX (controllers, reactive state, DI, routing).
- **Networking**: Dio with interceptors (auth token injection, refresh-on-401,
  unified error mapping). Typed DTO models + repositories over datasources.
- **Screens/modules**: Auth, Dashboard, Inventory (products/stores/movements),
  CSV Import, Forecasting, Model Evaluation, Alerts, Replenishment, Purchase
  Orders, Analytics, Settings.
- **Reusable components**: a shared async state widget handling
  loading / error / empty / offline, plus cards, charts, and list tiles.
- **Offline**: connectivity detection + cached last-good responses; explicit
  offline state in UI.
- **Config**: API base URL via environment (`--dart-define`).
- **Target platforms (DECIDED): Mobile + Web + Desktop.** Mobile = Android + iOS;
  Web = Flutter Web; Desktop = Windows/macOS/Linux. Web builds use the backend
  through a single API host (reverse-proxy rule applies); desktop/mobile hit the
  API base URL directly. CI builds/tests the shared Dart code; per-platform build
  jobs are added where the runner supports them.

---

## 10. Testing Strategy

DECIDED: SQLite (aiosqlite/sqlite) for fast unit and API tests; PostgreSQL for
integration tests and CI. SQLAlchemy models use portable column types where
possible; RLS- and Postgres-specific behavior is exercised only against Postgres.

| Layer | Tooling | Coverage |
|-------|---------|----------|
| Unit | pytest + SQLite | services, metrics, replenishment math, RBAC helpers |
| Integration | pytest + **Postgres** | CRUD, transactions/rollback, tenant isolation, RLS policies |
| API | pytest + SQLite + FastAPI TestClient/httpx | auth flows, endpoint contracts, error codes |
| ML | pytest | metric correctness on hand-computed data; no-look-ahead backtest assertions; determinism |
| Flutter | flutter_test | widgets, controllers, state transitions |

- CI (`GitHub Actions`): matrix job for backend (lint + tests, Postgres service)
  and Flutter (`analyze` + `test`). Runs on push/PR.
- Every phase ends with running its tests and fixing failures before moving on.

---

## 11. Infrastructure & Docs

- **Docker**: multi-stage backend `Dockerfile`; `docker-compose.yml` with `api` +
  `postgres` + healthchecks; migrations run on startup.
- **CI/CD**: GitHub Actions as above; optional build/publish image job.
- **Docs**: `README.md` (setup + env vars), `docs/ARCHITECTURE.md`,
  `docs/API.md`, `docs/ML.md`, `docs/DEPLOYMENT.md`, `.env.example`.

---

## 12. Phased Task Breakdown

| Phase | Scope | Primary deliverables | Verification |
|-------|-------|----------------------|--------------|
| 1 (now) | Repo inspection + plan | this document | Review/approval |
| 2 | Backend foundation | app skeleton, config, ORM models, Alembic migration, auth+RBAC, tenant isolation, synthetic seed, docker-compose, baseline tests | `pytest`, app boots, migration applies |
| 3 | Flutter core | app skeleton, Dio client, GetX routing/DI, Dashboard + Inventory screens on real APIs, async/offline states | `flutter analyze`/`test` (toolchain permitting) |
| 4 | CSV import | upload, validation, duplicate detection, error reports, UI | import tests + API tests |
| 5 | Forecasting & evaluation | features, baselines + models, backtesting, metrics, forecast/model endpoints, Evaluation screen | ML tests + API tests |
| 6 | Alerts, replenishment, PO | rules engine, reorder math, PO lifecycle with partial receipt, screens | service + API + transaction tests |
| 7 | Hardening & delivery | full test suites, Docker, CI/CD, documentation, reproducible demo data | green CI, docs complete |

---

## 13. Working Agreements

- Inspect files before modifying; implement real functionality (no stubs).
- Run tests after each phase; fix failures before advancing.
- Stop after each phase and report changed files, completed features, test
  results, and remaining tasks.
- Never commit unless explicitly asked.

---

## 14. Resolved Decisions

1. **Local toolchain**: Install **PostgreSQL only** in this environment so the
   backend can migrate and run integration tests locally. Docker and Flutter
   remain authored-only locally and are executed in CI.
2. **Multi-tenancy**: `org_id` service-layer filtering **plus PostgreSQL RLS**.
3. **Test database**: **SQLite** for fast unit/API tests; **PostgreSQL** for
   integration tests and CI.
4. **Flutter targets**: **Mobile + Web + Desktop.**

### Remaining environment caveat
Flutter/Dart is still not installed, so `flutter analyze`/`flutter test` and
platform builds cannot run in this environment; they will run in CI. If local
Flutter execution is later required, it can be installed on request.
