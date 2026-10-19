"""Organisation user management endpoints (admin/owner only)."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.api.deps import require_roles
from app.core.rbac import Role
from app.db.session import get_db
from app.models.user import User
from app.schemas.common import Page
from app.schemas.user import UserCreate, UserOut
from app.services import user_service

router = APIRouter(prefix="/users", tags=["users"])

AdminUser = Annotated[User, Depends(require_roles(Role.OWNER, Role.ADMIN))]


@router.get("", response_model=Page[UserOut], summary="List users in the organisation")
def list_users(
    admin: AdminUser,
    db: Annotated[Session, Depends(get_db)],
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> Page[UserOut]:
    users, total = user_service.list_users(db, org_id=admin.org_id, limit=limit, offset=offset)
    return Page[UserOut](
        items=[UserOut.model_validate(u) for u in users],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.post(
    "",
    response_model=UserOut,
    status_code=status.HTTP_201_CREATED,
    summary="Create a user in the organisation",
)
def create_user(
    payload: UserCreate,
    admin: AdminUser,
    db: Annotated[Session, Depends(get_db)],
) -> UserOut:
    user = user_service.create_user(
        db,
        org_id=admin.org_id,
        email=payload.email,
        password=payload.password,
        full_name=payload.full_name,
        role=payload.role,
    )
    return UserOut.model_validate(user)
