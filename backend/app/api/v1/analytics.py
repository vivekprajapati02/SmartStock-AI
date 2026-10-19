"""Analytics endpoints. All numbers come from stored data."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser
from app.db.session import get_db
from app.schemas.analytics import DashboardOut
from app.services import analytics_service

router = APIRouter(prefix="/analytics", tags=["analytics"])


@router.get("/dashboard", response_model=DashboardOut)
def dashboard(
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    trend_days: int = Query(default=30, ge=7, le=90),
) -> DashboardOut:
    return analytics_service.get_dashboard(db, org_id=user.org_id, trend_days=trend_days)
