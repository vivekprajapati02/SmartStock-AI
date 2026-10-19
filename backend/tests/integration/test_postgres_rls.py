"""PostgreSQL Row-Level Security integration tests.

These exercise the database-level guarantees that SQLite cannot provide. Data is
committed using stable identifiers so repeated runs reuse the same rows (no
accumulation and no deletes required).
"""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy import Engine, insert, text
from sqlalchemy.exc import DBAPIError

from app.core.security import hash_password
from app.models.organization import Organization
from app.models.user import User

pytestmark = pytest.mark.postgres


def _ensure_org(engine: Engine, slug: str, name: str) -> uuid.UUID:
    with engine.begin() as connection:
        existing = connection.execute(
            text("SELECT id FROM organizations WHERE slug = :slug"), {"slug": slug}
        ).scalar()
        if existing is not None:
            return existing
        org_id = uuid.uuid4()
        connection.execute(
            insert(Organization.__table__).values(
                id=org_id, name=name, slug=slug, is_demo=True
            )
        )
        return org_id


def _ensure_user(engine: Engine, org_id: uuid.UUID, email: str) -> uuid.UUID:
    with engine.begin() as connection:
        connection.execute(
            text("SELECT set_config('app.current_org', :org, true)"), {"org": str(org_id)}
        )
        existing = connection.execute(
            text("SELECT id FROM users WHERE org_id = :org AND email = :email"),
            {"org": str(org_id), "email": email},
        ).scalar()
        if existing is not None:
            return existing
        user_id = uuid.uuid4()
        connection.execute(
            insert(User.__table__).values(
                id=user_id,
                org_id=org_id,
                email=email,
                hashed_password=hash_password("rls-password-123"),
                role="viewer",
                is_active=True,
            )
        )
        return user_id


def test_rls_shows_only_the_current_org(pg_engine: Engine):
    org_a = _ensure_org(pg_engine, "rls-alpha", "RLS Alpha")
    org_b = _ensure_org(pg_engine, "rls-beta", "RLS Beta")
    _ensure_user(pg_engine, org_a, "alpha-user@rls-corp.com")
    _ensure_user(pg_engine, org_b, "beta-user@rls-corp.com")

    with pg_engine.connect() as connection:
        transaction = connection.begin()
        connection.execute(
            text("SELECT set_config('app.current_org', :org, true)"), {"org": str(org_a)}
        )
        visible = connection.execute(text("SELECT org_id FROM users")).scalars().all()
        assert visible, "expected at least one visible user"
        assert set(visible) == {org_a}
        transaction.rollback()

    with pg_engine.connect() as connection:
        transaction = connection.begin()
        connection.execute(
            text("SELECT set_config('app.current_org', :org, true)"), {"org": str(org_b)}
        )
        visible = connection.execute(text("SELECT org_id FROM users")).scalars().all()
        assert set(visible) == {org_b}
        transaction.rollback()


def test_rls_fails_closed_without_context(pg_engine: Engine):
    # Ensure at least one committed user row exists to prove it is still hidden.
    org = _ensure_org(pg_engine, "rls-gamma", "RLS Gamma")
    _ensure_user(pg_engine, org, "gamma-user@rls-corp.com")

    with pg_engine.connect() as connection:
        # No set_config: the context must be effectively NULL and RLS must hide
        # every row even though committed users exist.
        unset = connection.execute(
            text("SELECT NULLIF(current_setting('app.current_org', true), '') IS NULL")
        ).scalar()
        assert unset is True
        total = connection.execute(text("SELECT count(*) FROM users")).scalar()
        assert total == 0


def test_set_local_is_reset_between_transactions(pg_engine: Engine):
    org_a = _ensure_org(pg_engine, "rls-alpha", "RLS Alpha")
    with pg_engine.connect() as connection:
        with connection.begin():
            connection.execute(
                text("SELECT set_config('app.current_org', :org, true)"), {"org": str(org_a)}
            )
            inside = connection.execute(
                text("SELECT current_setting('app.current_org', true)")
            ).scalar()
            assert inside == str(org_a)
        # A new transaction on the same connection must start with no context.
        with connection.begin():
            after = connection.execute(
                text("SELECT NULLIF(current_setting('app.current_org', true), '') IS NULL")
            ).scalar()
            assert after is True


def test_rls_blocks_cross_org_insert(pg_engine: Engine):
    org_a = _ensure_org(pg_engine, "rls-alpha", "RLS Alpha")
    org_b = _ensure_org(pg_engine, "rls-beta", "RLS Beta")

    with pg_engine.connect() as connection:
        transaction = connection.begin()
        connection.execute(
            text("SELECT set_config('app.current_org', :org, true)"), {"org": str(org_a)}
        )
        with pytest.raises(DBAPIError):
            connection.execute(
                insert(User.__table__).values(
                    id=uuid.uuid4(),
                    org_id=org_b,  # different tenant -> WITH CHECK must reject
                    email=f"x{uuid.uuid4().hex}@rls-corp.com",
                    hashed_password="not-a-real-hash",
                    role="viewer",
                    is_active=True,
                )
            )
        transaction.rollback()


def test_app_auth_flow_works_under_rls(pg_client):
    register = pg_client.post(
        "/api/v1/auth/register",
        json={
            "organization_name": "RLS App Org",
            "organization_slug": "rls-app-org",
            "email": "owner@rls-app.com",
            "password": "password-123",
        },
    )
    assert register.status_code == 201, register.text
    token = register.json()["tokens"]["access_token"]

    me = pg_client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200

    users = pg_client.get("/api/v1/users", headers={"Authorization": f"Bearer {token}"})
    assert users.status_code == 200
    assert users.json()["total"] == 1
