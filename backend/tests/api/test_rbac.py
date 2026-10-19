"""API tests for role-based access control (SQLite)."""

from __future__ import annotations

from tests.helpers import USERS_URL, auth_header, login, register_org, tokens_from


def _create_user(client, owner_token, *, email, role, password="password-123"):
    return client.post(
        USERS_URL,
        headers=auth_header(owner_token),
        json={"email": email, "password": password, "full_name": "Test User", "role": role},
    )


def test_owner_can_list_and_create_users(client):
    owner_token = tokens_from(register_org(client))["access_token"]
    created = _create_user(client, owner_token, email="manager@acme-corp.com", role="manager")
    assert created.status_code == 201, created.text
    assert created.json()["role"] == "manager"

    listed = client.get(USERS_URL, headers=auth_header(owner_token))
    assert listed.status_code == 200
    assert listed.json()["total"] == 2


def test_viewer_cannot_list_or_create_users(client):
    owner_token = tokens_from(register_org(client))["access_token"]
    created = _create_user(client, owner_token, email="viewer@acme-corp.com", role="viewer")
    assert created.status_code == 201

    viewer_token = tokens_from(
        login(client, email="viewer@acme-corp.com", password="password-123")
    )["access_token"]

    listed = client.get(USERS_URL, headers=auth_header(viewer_token))
    assert listed.status_code == 403
    assert listed.json()["error"]["code"] == "permission_denied"

    forbidden = _create_user(client, viewer_token, email="x@acme-corp.com", role="viewer")
    assert forbidden.status_code == 403


def test_admin_can_manage_users(client):
    owner_token = tokens_from(register_org(client))["access_token"]
    _create_user(client, owner_token, email="admin@acme-corp.com", role="admin")

    admin_token = tokens_from(
        login(client, email="admin@acme-corp.com", password="password-123")
    )["access_token"]

    listed = client.get(USERS_URL, headers=auth_header(admin_token))
    assert listed.status_code == 200


def test_duplicate_email_in_same_org_conflicts(client):
    owner_token = tokens_from(register_org(client))["access_token"]
    created = _create_user(client, owner_token, email="dup@acme-corp.com", role="viewer")
    assert created.status_code == 201
    duplicate = _create_user(client, owner_token, email="dup@acme-corp.com", role="viewer")
    assert duplicate.status_code == 409
    assert duplicate.json()["error"]["code"] == "conflict"
