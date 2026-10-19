"""Replenishment, alerts and purchase-order endpoints."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser, require_roles
from app.core.rbac import Role
from app.db.session import get_db
from app.models.enums import AlertSeverity, AlertStatus, AlertType, PurchaseOrderStatus
from app.models.user import User
from app.schemas.alerts import AlertOut, AlertUpdate, EvaluateRequest, EvaluateResult
from app.schemas.common import Page
from app.schemas.purchasing import (
    FromRecommendationsRequest,
    FromRecommendationsResult,
    POCreate,
    PODetail,
    POOut,
    POUpdate,
    ReceiveRequest,
)
from app.schemas.replenishment import ApplyRequest, ApplyResult, ReplenishmentList
from app.services import (
    alert_service,
    purchase_order_service,
    replenishment_service,
)

ManagerUser = Annotated[User, Depends(require_roles(Role.OWNER, Role.ADMIN, Role.MANAGER))]
AdminUser = Annotated[User, Depends(require_roles(Role.OWNER, Role.ADMIN))]
DB = Annotated[Session, Depends(get_db)]

# ---------------------------------------------------------------- replenishment

replenishment_router = APIRouter(prefix="/replenishment", tags=["replenishment"])


@replenishment_router.get("", response_model=ReplenishmentList)
def list_replenishment(
    user: CurrentUser,
    db: DB,
    store_id: uuid.UUID | None = Query(default=None),
    needs_reorder: bool | None = Query(default=None),
    service_level: float = Query(default=0.95, ge=0.5, le=0.999),
    review_days: int = Query(default=7, ge=1, le=90),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> ReplenishmentList:
    """Reorder point, safety stock, target and recommended quantity per SKU/store,
    computed from stored sales, forecasts and open purchase orders."""
    items, history_end = replenishment_service.compute(
        db,
        org_id=user.org_id,
        service_level=service_level,
        review_days=review_days,
        store_id=store_id,
    )
    if needs_reorder is not None:
        items = [i for i in items if i.needs_reorder == needs_reorder]
    # Items to reorder first, largest recommendation first.
    items.sort(key=lambda i: (not i.needs_reorder, -i.recommended_qty, i.sku))
    return ReplenishmentList(
        items=items[offset : offset + limit],
        total=len(items),
        limit=limit,
        offset=offset,
        service_level=service_level,
        z_score=round(replenishment_service.z_for(service_level), 4),
        review_days=review_days,
        history_days=56,
        history_end=history_end.isoformat() if history_end else None,
    )


@replenishment_router.post("/apply", response_model=ApplyResult)
def apply_replenishment(payload: ApplyRequest, user: ManagerUser, db: DB) -> ApplyResult:
    """Store the computed reorder points and safety stock on inventory rows."""
    updated = replenishment_service.apply(
        db,
        org_id=user.org_id,
        service_level=payload.service_level,
        review_days=payload.review_days,
        store_id=payload.store_id,
        inventory_ids=payload.inventory_ids,
    )
    return ApplyResult(updated=updated)


# ---------------------------------------------------------------- alerts

alerts_router = APIRouter(tags=["alerts"])


@alerts_router.get("/alerts", response_model=Page[AlertOut])
def list_alerts(
    user: CurrentUser,
    db: DB,
    status_: AlertStatus | None = Query(default=None, alias="status"),
    alert_type: AlertType | None = Query(default=None),
    severity: AlertSeverity | None = Query(default=None),
    store_id: uuid.UUID | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> Page[AlertOut]:
    items, total = alert_service.list_alerts(
        db,
        org_id=user.org_id,
        limit=limit,
        offset=offset,
        status=status_,
        alert_type=alert_type,
        severity=severity,
        store_id=store_id,
    )
    return Page[AlertOut](items=items, total=total, limit=limit, offset=offset)


@alerts_router.post("/alerts:evaluate", response_model=EvaluateResult)
def evaluate_alerts(payload: EvaluateRequest, user: ManagerUser, db: DB) -> EvaluateResult:
    """Re-check every SKU/store against the alert rules."""
    return alert_service.evaluate(
        db,
        org_id=user.org_id,
        service_level=payload.service_level,
        review_days=payload.review_days,
    )


@alerts_router.patch("/alerts/{alert_id}", response_model=AlertOut)
def update_alert(
    alert_id: uuid.UUID, payload: AlertUpdate, user: ManagerUser, db: DB
) -> AlertOut:
    return alert_service.update_status(
        db, org_id=user.org_id, alert_id=alert_id, status=AlertStatus(payload.status)
    )


# ---------------------------------------------------------------- purchase orders

po_router = APIRouter(prefix="/purchase-orders", tags=["purchase-orders"])


@po_router.get("", response_model=Page[POOut])
def list_purchase_orders(
    user: CurrentUser,
    db: DB,
    status_: PurchaseOrderStatus | None = Query(default=None, alias="status"),
    supplier_id: uuid.UUID | None = Query(default=None),
    store_id: uuid.UUID | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> Page[POOut]:
    items, total = purchase_order_service.list_orders(
        db,
        org_id=user.org_id,
        limit=limit,
        offset=offset,
        status=status_,
        supplier_id=supplier_id,
        store_id=store_id,
    )
    return Page[POOut](items=items, total=total, limit=limit, offset=offset)


@po_router.post("", response_model=PODetail, status_code=status.HTTP_201_CREATED)
def create_purchase_order(payload: POCreate, user: ManagerUser, db: DB) -> PODetail:
    po = purchase_order_service.create(
        db,
        org_id=user.org_id,
        user_id=user.id,
        supplier_id=payload.supplier_id,
        store_id=payload.store_id,
        reference=payload.reference,
        expected_date=payload.expected_date,
        items=payload.items,
    )
    return purchase_order_service.detail(db, po)


@po_router.post(
    "/from-recommendations",
    response_model=FromRecommendationsResult,
    status_code=status.HTTP_201_CREATED,
)
def create_from_recommendations(
    payload: FromRecommendationsRequest, user: ManagerUser, db: DB
) -> FromRecommendationsResult:
    """Draft one order per supplier for the store's recommended quantities."""
    return purchase_order_service.from_recommendations(
        db,
        org_id=user.org_id,
        user_id=user.id,
        store_id=payload.store_id,
        service_level=payload.service_level,
        review_days=payload.review_days,
    )


@po_router.get("/{po_id}", response_model=PODetail)
def get_purchase_order(po_id: uuid.UUID, user: CurrentUser, db: DB) -> PODetail:
    return purchase_order_service.detail(
        db, purchase_order_service.get(db, org_id=user.org_id, po_id=po_id)
    )


@po_router.patch("/{po_id}", response_model=PODetail)
def update_purchase_order(
    po_id: uuid.UUID, payload: POUpdate, user: ManagerUser, db: DB
) -> PODetail:
    po = purchase_order_service.update(
        db,
        org_id=user.org_id,
        po_id=po_id,
        fields=payload.model_dump(exclude_unset=True),
    )
    return purchase_order_service.detail(db, po)


def _transition(action: str):
    def handler(po_id: uuid.UUID, user: User, db: Session) -> PODetail:
        po = purchase_order_service.transition(
            db, org_id=user.org_id, po_id=po_id, action=action, user_id=user.id
        )
        return purchase_order_service.detail(db, po)

    return handler


@po_router.post("/{po_id}/submit", response_model=PODetail)
def submit_purchase_order(po_id: uuid.UUID, user: ManagerUser, db: DB) -> PODetail:
    return _transition("submit")(po_id, user, db)


@po_router.post("/{po_id}/approve", response_model=PODetail)
def approve_purchase_order(po_id: uuid.UUID, user: AdminUser, db: DB) -> PODetail:
    """Admins and owners only."""
    return _transition("approve")(po_id, user, db)


@po_router.post("/{po_id}/cancel", response_model=PODetail)
def cancel_purchase_order(po_id: uuid.UUID, user: ManagerUser, db: DB) -> PODetail:
    return _transition("cancel")(po_id, user, db)


@po_router.post("/{po_id}/receive", response_model=PODetail)
def receive_purchase_order(
    po_id: uuid.UUID, payload: ReceiveRequest, user: ManagerUser, db: DB
) -> PODetail:
    """Receive some or all remaining quantities in one transaction."""
    po = purchase_order_service.receive(
        db, org_id=user.org_id, po_id=po_id, lines=payload.lines, note=payload.note
    )
    return purchase_order_service.detail(db, po)
