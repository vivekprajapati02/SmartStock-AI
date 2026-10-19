"""Unit tests for password hashing and JWT tokens."""

from __future__ import annotations

import time
from datetime import UTC, datetime, timedelta

import jwt
import pytest

from app.core.config import get_settings
from app.core.errors import AuthenticationError
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    verify_password,
)


def test_hash_is_verifiable():
    hashed = hash_password("s3cret-password")
    assert hashed != "s3cret-password"
    assert hashed.startswith("$2")
    assert verify_password("s3cret-password", hashed)
    assert not verify_password("wrong-password", hashed)


def test_hashes_are_salted():
    assert hash_password("same-password") != hash_password("same-password")


def test_verify_rejects_malformed_hash():
    assert not verify_password("whatever", "not-a-bcrypt-hash")


def test_password_longer_than_72_bytes_is_rejected():
    with pytest.raises(ValueError):
        hash_password("a" * 73)


def test_access_token_roundtrip():
    token = create_access_token(subject="user-1", org_id="org-1", role="owner")
    payload = decode_token(token, expected_type="access")
    assert payload["sub"] == "user-1"
    assert payload["org"] == "org-1"
    assert payload["role"] == "owner"


def test_refresh_token_cannot_be_used_as_access():
    token = create_refresh_token(subject="user-1", org_id="org-1")
    with pytest.raises(AuthenticationError):
        decode_token(token, expected_type="access")


def test_tampered_token_is_rejected():
    token = create_access_token(subject="user-1", org_id="org-1", role="viewer")
    tampered = token[:-2] + ("AA" if not token.endswith("AA") else "BB")
    with pytest.raises(AuthenticationError):
        decode_token(tampered)


def test_expired_token_is_rejected():
    settings = get_settings()
    expired = jwt.encode(
        {
            "sub": "user-1",
            "org": "org-1",
            "type": "access",
            "iat": int(time.time()) - 7200,
            "exp": int(time.time()) - 3600,
        },
        settings.jwt_secret_key,
        algorithm=settings.jwt_algorithm,
    )
    with pytest.raises(AuthenticationError):
        decode_token(expired)


def test_token_signed_with_other_secret_is_rejected():
    forged = jwt.encode(
        {
            "sub": "user-1",
            "org": "org-1",
            "type": "access",
            "exp": datetime.now(UTC) + timedelta(minutes=5),
        },
        "a-different-secret",
        algorithm="HS256",
    )
    with pytest.raises(AuthenticationError):
        decode_token(forged)
