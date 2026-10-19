"""Password hashing and JWT token helpers.

Passwords are hashed with bcrypt (per-password salt, cost factor configured by
the library). JWTs are signed with HS256 using ``JWT_SECRET_KEY`` and carry a
``type`` claim so an access token can never be replayed as a refresh token.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import bcrypt
import jwt

from app.core.config import get_settings
from app.core.errors import AuthenticationError

# bcrypt only considers the first 72 bytes of a password and raises otherwise.
_BCRYPT_MAX_BYTES = 72

ACCESS_TOKEN_TYPE = "access"
REFRESH_TOKEN_TYPE = "refresh"


def hash_password(password: str) -> str:
    password_bytes = password.encode("utf-8")
    if len(password_bytes) > _BCRYPT_MAX_BYTES:
        raise ValueError("Password is too long (maximum 72 bytes when UTF-8 encoded).")
    return bcrypt.hashpw(password_bytes, bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, hashed_password: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode("utf-8"), hashed_password.encode("utf-8"))
    except (ValueError, TypeError):
        # Malformed hash in storage must never authenticate a user.
        return False


def _create_token(
    *,
    subject: str,
    org_id: str,
    token_type: str,
    expires_delta: timedelta,
    role: str | None = None,
) -> str:
    settings = get_settings()
    now = datetime.now(UTC)
    payload: dict[str, Any] = {
        "sub": subject,
        "org": org_id,
        "type": token_type,
        "iat": int(now.timestamp()),
        "exp": int((now + expires_delta).timestamp()),
        "jti": uuid.uuid4().hex,
    }
    if role is not None:
        payload["role"] = role
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def create_access_token(*, subject: str, org_id: str, role: str) -> str:
    settings = get_settings()
    return _create_token(
        subject=subject,
        org_id=org_id,
        token_type=ACCESS_TOKEN_TYPE,
        role=role,
        expires_delta=timedelta(minutes=settings.access_token_expire_minutes),
    )


def create_refresh_token(*, subject: str, org_id: str) -> str:
    settings = get_settings()
    return _create_token(
        subject=subject,
        org_id=org_id,
        token_type=REFRESH_TOKEN_TYPE,
        expires_delta=timedelta(days=settings.refresh_token_expire_days),
    )


def decode_token(token: str, *, expected_type: str | None = None) -> dict[str, Any]:
    settings = get_settings()
    try:
        payload = jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
    except jwt.ExpiredSignatureError as exc:
        raise AuthenticationError("Token has expired.") from exc
    except jwt.PyJWTError as exc:
        raise AuthenticationError("Token is invalid.") from exc

    if expected_type is not None and payload.get("type") != expected_type:
        raise AuthenticationError("Unexpected token type.")
    if not payload.get("sub") or not payload.get("org"):
        raise AuthenticationError("Token is missing required claims.")
    return payload
