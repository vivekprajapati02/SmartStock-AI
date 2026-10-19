"""Engine, session factory, and tenant-aware DB dependencies.

The ``after_begin`` listener below is the single place where the PostgreSQL RLS
session variable is applied. Because it runs at the start of *every* transaction
on a session that carries an organisation in ``session.info``, the tenant
context survives commits (a new transaction re-applies it) and is automatically
cleared by ``SET LOCAL`` semantics when the transaction ends, so nothing leaks
back to the connection pool.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator

from sqlalchemy import create_engine, event, text
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import get_settings

# Key under which the current organisation id is stored on ``Session.info``.
ORG_CONTEXT_KEY = "org_id"

_settings = get_settings()

engine = create_engine(_settings.database_url, **_settings.sqlalchemy_engine_kwargs())

SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
    autocommit=False,
    expire_on_commit=False,
    class_=Session,
)


def _apply_context(connection, org_id: str) -> None:
    if connection.dialect.name != "postgresql":
        return
    connection.execute(
        text("SELECT set_config('app.current_org', :org, true)"),
        {"org": str(org_id)},
    )


@event.listens_for(Session, "after_begin")
def _apply_rls_context(session: Session, transaction, connection) -> None:  # noqa: ANN001
    """Set ``app.current_org`` for PostgreSQL so RLS policies can filter rows."""
    org_id = session.info.get(ORG_CONTEXT_KEY)
    if org_id is None:
        return
    _apply_context(connection, str(org_id))


def set_org_context(session: Session, org_id: uuid.UUID | str) -> None:
    """Bind the session to an organisation for tenant-scoped access.

    If a transaction is already open the setting is applied immediately;
    otherwise the ``after_begin`` listener applies it when the next transaction
    starts. This makes the call safe both before and after the first flush.
    """
    session.info[ORG_CONTEXT_KEY] = str(org_id)
    if session.in_transaction():
        _apply_context(session.connection(), str(org_id))


def clear_org_context(session: Session) -> None:
    session.info.pop(ORG_CONTEXT_KEY, None)


def get_db() -> Iterator[Session]:
    """FastAPI dependency yielding a request-scoped session."""
    db = SessionLocal()
    try:
        yield db
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()
