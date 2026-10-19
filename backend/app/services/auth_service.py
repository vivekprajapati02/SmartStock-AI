"""Authentication and organisation provisioning business logic."""

from __future__ import annotations

import re
import uuid

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.errors import AuthenticationError, ConflictError
from app.core.logging import get_logger
from app.core.rbac import Role
from app.core.security import (
    REFRESH_TOKEN_TYPE,
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    verify_password,
)
from app.db.session import set_org_context
from app.models.organization import Organization
from app.models.user import User
from app.schemas.auth import AuthResponse, TokenPair

logger = get_logger(__name__)


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.strip().lower()).strip("-")
    return slug[:80] or "org"


def _token_pair(user: User) -> TokenPair:
    settings = get_settings()
    return TokenPair(
        access_token=create_access_token(
            subject=str(user.id), org_id=str(user.org_id), role=str(user.role)
        ),
        refresh_token=create_refresh_token(subject=str(user.id), org_id=str(user.org_id)),
        expires_in=settings.access_token_expire_minutes * 60,
    )


def _auth_response(user: User) -> AuthResponse:
    return AuthResponse(user=user, tokens=_token_pair(user))  # type: ignore[arg-type]


def register_organization(
    db: Session,
    *,
    organization_name: str,
    organization_slug: str | None,
    email: str,
    password: str,
    full_name: str | None,
) -> AuthResponse:
    slug = slugify(organization_slug or organization_name)
    email = email.strip().lower()

    existing = db.execute(
        select(Organization).where(
            (Organization.slug == slug) | (Organization.name == organization_name)
        )
    ).scalar_one_or_none()
    if existing is not None:
        raise ConflictError("An organisation with this name or slug already exists.")

    org = Organization(id=uuid.uuid4(), name=organization_name, slug=slug, is_demo=False)
    db.add(org)
    # Bind the session to the new org before inserting the owner (RLS WITH CHECK).
    set_org_context(db, org.id)
    user = User(
        id=uuid.uuid4(),
        org_id=org.id,
        email=email,
        hashed_password=hash_password(password),
        full_name=full_name,
        role=Role.OWNER,
        is_active=True,
    )
    db.add(user)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise ConflictError("An organisation with this name or slug already exists.") from exc

    db.refresh(user)
    logger.info("Registered organisation %s with owner %s", slug, email)
    return _auth_response(user)


def authenticate(
    db: Session, *, organization: str, email: str, password: str
) -> AuthResponse:
    slug = slugify(organization)
    email = email.strip().lower()

    org = db.execute(
        select(Organization).where(Organization.slug == slug)
    ).scalar_one_or_none()
    # A single generic error message avoids leaking which part was wrong.
    if org is None:
        raise AuthenticationError("Invalid organisation, email, or password.")
    set_org_context(db, org.id)

    user = db.execute(
        select(User).where(User.org_id == org.id, User.email == email)
    ).scalar_one_or_none()
    if user is None or not user.is_active or not verify_password(password, user.hashed_password):
        raise AuthenticationError("Invalid organisation, email, or password.")

    return _auth_response(user)


def refresh_tokens(db: Session, *, refresh_token: str) -> AuthResponse:
    payload = decode_token(refresh_token, expected_type=REFRESH_TOKEN_TYPE)
    user_id = payload["sub"]
    org_id = payload["org"]
    set_org_context(db, org_id)

    user = db.get(User, uuid.UUID(user_id))
    if user is None or user.org_id != uuid.UUID(org_id) or not user.is_active:
        raise AuthenticationError("Refresh token is no longer valid.")

    return _auth_response(user)
