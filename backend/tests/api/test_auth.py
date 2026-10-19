"""API tests for authentication endpoints (SQLite)."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.user import User
from tests.helpers import (
    DEFAULT_PASSWORD,
    ME_URL,
    REFRESH_URL,
    auth_header,
    login,
    register_org,
    tokens_from,
)


def test_register_creates_organisation_and_owner(client):
    response = register_org(client)
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["user"]["role"] == "owner"
    assert body["user"]["email"] == "owner@acme-corp.com"
    assert body["user"]["org_id"]
    assert body["tokens"]["access_token"]
    assert body["tokens"]["refresh_token"]
    assert body["tokens"]["token_type"] == "bearer"
    assert body["tokens"]["expires_in"] > 0


def test_register_duplicate_organisation_conflicts(client):
    assert register_org(client).status_code == 201
    response = register_org(client, email="other@acme-corp.com")
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "conflict"


def test_register_rejects_weak_password(client):
    response = register_org(client, password="short")
    assert response.status_code == 422
    body = response.json()
    assert body["error"]["code"] == "validation_error"
    assert any(detail["field"] == "password" for detail in body["error"]["details"])


def test_register_rejects_invalid_email(client):
    response = register_org(client, email="not-an-email")
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


def test_login_success(client):
    register_org(client)
    response = login(client)
    assert response.status_code == 200, response.text
    assert response.json()["tokens"]["access_token"]


def test_login_wrong_password(client):
    register_org(client)
    response = login(client, password="wrong-password")
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthenticated"


def test_login_unknown_organisation(client):
    response = login(client, organization="does-not-exist")
    assert response.status_code == 401


def test_me_requires_token(client):
    response = client.get(ME_URL)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthenticated"


def test_me_rejects_invalid_token(client):
    response = client.get(ME_URL, headers=auth_header("not-a-real-token"))
    assert response.status_code == 401


def test_me_returns_current_user(client):
    tokens = tokens_from(register_org(client))
    response = client.get(ME_URL, headers=auth_header(tokens["access_token"]))
    assert response.status_code == 200
    assert response.json()["email"] == "owner@acme-corp.com"


def test_refresh_issues_new_tokens(client):
    tokens = tokens_from(register_org(client))
    response = client.post(REFRESH_URL, json={"refresh_token": tokens["refresh_token"]})
    assert response.status_code == 200
    assert response.json()["tokens"]["access_token"]


def test_refresh_rejects_access_token(client):
    tokens = tokens_from(register_org(client))
    response = client.post(REFRESH_URL, json={"refresh_token": tokens["access_token"]})
    assert response.status_code == 401


def test_password_is_never_stored_in_plaintext(client, db: Session):
    register_org(client, password=DEFAULT_PASSWORD)
    user = db.execute(select(User).where(User.email == "owner@acme-corp.com")).scalar_one()
    assert user.hashed_password != DEFAULT_PASSWORD
    assert DEFAULT_PASSWORD not in user.hashed_password
    assert user.hashed_password.startswith("$2")


def test_error_envelope_contains_request_id(client):
    response = client.get(ME_URL)
    assert response.status_code == 401
    assert response.json()["error"]["request_id"]
    assert response.headers["x-request-id"]


def test_health_endpoints(client):
    live = client.get("/health")
    assert live.status_code == 200
    assert live.json()["status"] == "ok"
    ready = client.get("/health/ready")
    assert ready.status_code == 200
    assert ready.json()["database"] == "ok"
