"""Organisation isolation tests at the service/API layer (SQLite)."""

from __future__ import annotations

from tests.helpers import USERS_URL, auth_header, register_org, tokens_from


def _register_two_orgs(client):
    tokens_a = tokens_from(
        register_org(
            client,
            organization_name="Alpha Inc",
            organization_slug="alpha",
            email="owner@alpha-corp.com",
        )
    )
    tokens_b = tokens_from(
        register_org(
            client,
            organization_name="Beta Inc",
            organization_slug="beta",
            email="owner@beta-corp.com",
        )
    )
    return tokens_a, tokens_b


def test_listing_users_is_scoped_to_the_callers_org(client):
    tokens_a, tokens_b = _register_two_orgs(client)

    # Add a second user to org A only.
    client.post(
        USERS_URL,
        headers=auth_header(tokens_a["access_token"]),
        json={"email": "extra@alpha-corp.com", "password": "password-123", "role": "viewer"},
    )

    listed_a = client.get(USERS_URL, headers=auth_header(tokens_a["access_token"])).json()
    listed_b = client.get(USERS_URL, headers=auth_header(tokens_b["access_token"])).json()

    assert listed_a["total"] == 2
    assert listed_b["total"] == 1
    emails_a = {item["email"] for item in listed_a["items"]}
    assert emails_a == {"owner@alpha-corp.com", "extra@alpha-corp.com"}
    assert {item["email"] for item in listed_b["items"]} == {"owner@beta-corp.com"}


def test_same_email_allowed_in_different_orgs(client):
    tokens_a, tokens_b = _register_two_orgs(client)

    shared_email = "shared@example.com"
    created_a = client.post(
        USERS_URL,
        headers=auth_header(tokens_a["access_token"]),
        json={"email": shared_email, "password": "password-123", "role": "viewer"},
    )
    created_b = client.post(
        USERS_URL,
        headers=auth_header(tokens_b["access_token"]),
        json={"email": shared_email, "password": "password-123", "role": "viewer"},
    )
    assert created_a.status_code == 201
    assert created_b.status_code == 201
    assert created_a.json()["org_id"] != created_b.json()["org_id"]
