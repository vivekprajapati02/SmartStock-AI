"""Shared FastAPI dependencies: authentication, tenant context, RBAC."""

from __future__ import annotations

import uuid
from collections.abc import Callable
from typing import Annotated

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.errors import AuthenticationError, PermissionDeniedError
from app.core.rbac import Role, role_at_least
from app.core.security import ACCESS_TOKEN_TYPE, decode_token
from app.db.session import get_db, set_org_context
from app.models.user import User

_bearer_scheme = HTTPBearer(auto_error=False)


def get_current_user(
    request: Request,
    db: Annotated[Session, Depends(get_db)],
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer_scheme)],
) -> User:
    if credentials is None or not credentials.credentials:
        raise AuthenticationError("Authorization header with a bearer token is required.")

    payload = decode_token(credentials.credentials, expected_type=ACCESS_TOKEN_TYPE)
    org_id = uuid.UUID(payload["org"])
    user_id = uuid.UUID(payload["sub"])

    # Establish tenant context before any org-scoped read (also feeds RLS).
    set_org_context(db, org_id)
    request.state.org_id = str(org_id)

    user = db.get(User, user_id)
    if user is None or user.org_id != org_id or not user.is_active:
        raise AuthenticationError("User account is not available.")
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


def require_roles(*roles: Role) -> Callable[..., User]:
    """Dependency factory requiring the caller to hold at least one role."""

    allowed = {Role(role) for role in roles}

    def _dependency(user: CurrentUser) -> User:
        # Higher-ranked roles satisfy lower-ranked requirements.
        if any(role_at_least(user.role, allowed_role) for allowed_role in allowed):
            return user
        raise PermissionDeniedError("Your role is not permitted to perform this action.")

    return _dependency
