"""Authentication endpoints: register, login, refresh, and current user."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser
from app.db.session import get_db
from app.schemas.auth import (
    AuthResponse,
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
)
from app.schemas.user import UserOut
from app.services import auth_service

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post(
    "/register",
    response_model=AuthResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Register an organisation and its owner user",
)
def register(payload: RegisterRequest, db: Annotated[Session, Depends(get_db)]) -> AuthResponse:
    return auth_service.register_organization(
        db,
        organization_name=payload.organization_name,
        organization_slug=payload.organization_slug,
        email=payload.email,
        password=payload.password,
        full_name=payload.full_name,
    )


@router.post("/login", response_model=AuthResponse, summary="Log in")
def login(payload: LoginRequest, db: Annotated[Session, Depends(get_db)]) -> AuthResponse:
    return auth_service.authenticate(
        db,
        organization=payload.organization,
        email=payload.email,
        password=payload.password,
    )


@router.post("/refresh", response_model=AuthResponse, summary="Exchange a refresh token")
def refresh(payload: RefreshRequest, db: Annotated[Session, Depends(get_db)]) -> AuthResponse:
    return auth_service.refresh_tokens(db, refresh_token=payload.refresh_token)


@router.get("/me", response_model=UserOut, summary="Get the current user")
def me(user: CurrentUser) -> UserOut:
    return UserOut.model_validate(user)
