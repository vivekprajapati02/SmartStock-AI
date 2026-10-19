"""Test helper utilities (not a test module)."""

from __future__ import annotations

from fastapi.testclient import TestClient

DEFAULT_PASSWORD = "password-123"

REGISTER_URL = "/api/v1/auth/register"
LOGIN_URL = "/api/v1/auth/login"
REFRESH_URL = "/api/v1/auth/refresh"
ME_URL = "/api/v1/auth/me"
USERS_URL = "/api/v1/users"


def register_org(
    client: TestClient,
    *,
    organization_name: str = "Acme Corp",
    organization_slug: str | None = None,
    email: str = "owner@acme-corp.com",
    password: str = DEFAULT_PASSWORD,
    full_name: str = "Owner",
):
    payload = {
        "organization_name": organization_name,
        "organization_slug": organization_slug,
        "email": email,
        "password": password,
        "full_name": full_name,
    }
    return client.post(REGISTER_URL, json=payload)


def login(
    client: TestClient,
    *,
    organization: str = "acme-corp",
    email: str = "owner@acme-corp.com",
    password: str = DEFAULT_PASSWORD,
):
    return client.post(
        LOGIN_URL,
        json={"organization": organization, "email": email, "password": password},
    )


def auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def tokens_from(response) -> dict[str, str]:
    return response.json()["tokens"]
