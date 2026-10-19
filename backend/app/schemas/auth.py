"""Authentication schemas."""

from __future__ import annotations

from pydantic import EmailStr, Field, field_validator

from app.schemas.common import APIModel
from app.schemas.user import UserOut

# bcrypt only hashes the first 72 bytes; reject longer passwords up front.
_MAX_PASSWORD_BYTES = 72


def _validate_password(value: str) -> str:
    if len(value) < 8:
        raise ValueError("Password must be at least 8 characters long.")
    if len(value.encode("utf-8")) > _MAX_PASSWORD_BYTES:
        raise ValueError("Password must be at most 72 bytes when UTF-8 encoded.")
    return value


class RegisterRequest(APIModel):
    """Creates a new organisation and its owner user."""

    organization_name: str = Field(min_length=2, max_length=200)
    organization_slug: str | None = Field(default=None, max_length=80)
    email: EmailStr
    password: str
    full_name: str | None = Field(default=None, max_length=200)

    @field_validator("password")
    @classmethod
    def _password(cls, value: str) -> str:
        return _validate_password(value)


class LoginRequest(APIModel):
    organization: str = Field(description="Organisation slug.", min_length=1, max_length=80)
    email: EmailStr
    password: str


class RefreshRequest(APIModel):
    refresh_token: str


class TokenPair(APIModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int = Field(description="Access-token lifetime in seconds.")


class AuthResponse(APIModel):
    user: UserOut
    tokens: TokenPair
