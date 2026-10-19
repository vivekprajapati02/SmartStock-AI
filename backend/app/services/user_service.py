"""User management within an organisation (org-scoped)."""

from __future__ import annotations

import uuid

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.errors import ConflictError
from app.core.rbac import Role
from app.core.security import hash_password
from app.db.session import set_org_context
from app.models.user import User


def create_user(
    db: Session,
    *,
    org_id: uuid.UUID,
    email: str,
    password: str,
    full_name: str | None,
    role: Role,
) -> User:
    set_org_context(db, org_id)
    email = email.strip().lower()
    existing = db.execute(
        select(User).where(User.org_id == org_id, User.email == email)
    ).scalar_one_or_none()
    if existing is not None:
        raise ConflictError("A user with this email already exists in the organisation.")

    user = User(
        id=uuid.uuid4(),
        org_id=org_id,
        email=email,
        hashed_password=hash_password(password),
        full_name=full_name,
        role=role,
        is_active=True,
    )
    db.add(user)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise ConflictError("A user with this email already exists in the organisation.") from exc
    db.refresh(user)
    return user


def list_users(
    db: Session, *, org_id: uuid.UUID, limit: int, offset: int
) -> tuple[list[User], int]:
    set_org_context(db, org_id)
    total = db.execute(
        select(func.count()).select_from(User).where(User.org_id == org_id)
    ).scalar_one()
    users = (
        db.execute(
            select(User)
            .where(User.org_id == org_id)
            .order_by(User.created_at, User.email)
            .limit(limit)
            .offset(offset)
        )
        .scalars()
        .all()
    )
    return list(users), int(total)
