"""User-facing schemas."""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import EmailStr, Field, field_validator

from app.core.rbac import Role
from app.schemas.common import APIModel


class UserOut(APIModel):
    id: uuid.UUID
    org_id: uuid.UUID
    email: str
    full_name: str | None = None
    role: Role
    is_active: bool
    created_at: datetime


class UserCreate(APIModel):
    email: EmailStr
    password: str
    full_name: str | None = Field(default=None, max_length=200)
    role: Role = Role.VIEWER

    @field_validator("password")
    @classmethod
    def _password(cls, value: str) -> str:
        if len(value) < 8:
            raise ValueError("Password must be at least 8 characters long.")
        if len(value.encode("utf-8")) > 72:
            raise ValueError("Password must be at most 72 bytes when UTF-8 encoded.")
        return value
