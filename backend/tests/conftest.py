"""Shared pytest fixtures.

Two databases are supported:

* **SQLite in-memory** for fast unit/API tests. Each test gets a fresh database,
  and the session runs inside an outer transaction with savepoints so service
  ``commit()`` calls never persist past the test.
* **PostgreSQL** (``TEST_DATABASE_URL``) for integration tests covering RLS and
  transaction behaviour. Tests are skipped when no server is reachable.

Because the app's ``get_db`` dependency is overridden, the SQLite and Postgres
fixtures plug straight into the FastAPI test client.
"""

from __future__ import annotations

import os
from collections.abc import Iterator
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Engine, create_engine, text
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import get_settings
from app.db.session import get_db
from app.main import app
from app.models import Base

BACKEND_DIR = Path(__file__).resolve().parent.parent
ALEMBIC_INI = BACKEND_DIR / "alembic.ini"


def _make_sqlite_engine() -> Engine:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    return engine


@pytest.fixture()
def sqlite_engine() -> Iterator[Engine]:
    engine = _make_sqlite_engine()
    try:
        yield engine
    finally:
        engine.dispose()


def _savepoint_session(engine: Engine) -> tuple[Session, object, object]:
    connection = engine.connect()
    transaction = connection.begin()
    session = Session(
        bind=connection,
        join_transaction_mode="create_savepoint",
        expire_on_commit=False,
        future=True,
    )
    return session, connection, transaction


@pytest.fixture()
def db(sqlite_engine: Engine) -> Iterator[Session]:
    session, connection, transaction = _savepoint_session(sqlite_engine)
    try:
        yield session
    finally:
        session.close()
        transaction.rollback()
        connection.close()


@pytest.fixture()
def client(db: Session) -> Iterator[TestClient]:
    def _override_get_db() -> Iterator[Session]:
        yield db

    app.dependency_overrides[get_db] = _override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


# --- PostgreSQL fixtures -------------------------------------------------


def _postgres_url() -> str | None:
    return os.environ.get("TEST_DATABASE_URL") or get_settings().test_database_url


@pytest.fixture(scope="session")
def postgres_url() -> str:
    url = _postgres_url()
    if not url or url.startswith("sqlite"):
        pytest.skip("TEST_DATABASE_URL is not configured; skipping PostgreSQL tests.")
    try:
        probe = create_engine(url)
        with probe.connect() as connection:
            connection.execute(text("SELECT 1"))
        probe.dispose()
    except Exception as exc:  # noqa: BLE001
        pytest.skip(f"PostgreSQL is not reachable ({exc}); skipping.")

    from alembic.config import Config

    from alembic import command

    config = Config(str(ALEMBIC_INI))
    config.set_main_option("script_location", str(BACKEND_DIR / "alembic"))
    config.set_main_option("sqlalchemy.url", url)
    command.upgrade(config, "head")
    return url


@pytest.fixture()
def pg_engine(postgres_url: str) -> Iterator[Engine]:
    engine = create_engine(postgres_url, pool_pre_ping=True, future=True)
    try:
        yield engine
    finally:
        engine.dispose()


@pytest.fixture()
def pg_db(pg_engine: Engine) -> Iterator[Session]:
    session, connection, transaction = _savepoint_session(pg_engine)
    try:
        yield session
    finally:
        session.close()
        transaction.rollback()
        connection.close()


@pytest.fixture()
def pg_client(postgres_url: str) -> Iterator[TestClient]:
    """A test client bound to PostgreSQL with transaction-scoped isolation."""
    engine = create_engine(postgres_url, pool_pre_ping=True, future=True)
    session, connection, transaction = _savepoint_session(engine)

    def _override_get_db() -> Iterator[Session]:
        yield session

    app.dependency_overrides[get_db] = _override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
    session.close()
    transaction.rollback()
    connection.close()
    engine.dispose()


@pytest.fixture()
def session_factory(sqlite_engine: Engine) -> sessionmaker:
    return sessionmaker(bind=sqlite_engine, expire_on_commit=False, future=True)
