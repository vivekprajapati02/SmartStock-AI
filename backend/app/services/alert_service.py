"""Rule-based stock alerts derived from inventory, sales and open orders.

Rules (per SKU/store, evaluated by ``evaluate``):

* ``low_stock``     0 < on hand <= the row's stored reorder point.
                    high if on hand <= stored safety stock, else medium.
* ``stockout_risk`` demand > 0 and on hand + on order < expected demand over
                    the lead time (stock runs out before a new order could
                    arrive). critical if already at 0, else high.
* ``overstock``     demand > 0 and days of cover > max(60, 3 x (lead + review)).
                    medium if more than twice that threshold, else low.
* ``slow_moving``   on hand > 0, the organisation has sales in the last 30
                    days, but this SKU/store has none. low.

De-duplication: one alert per (product, store, type) that is not resolved.
Open/acknowledged alerts are updated while the condition holds and resolved
automatically when it clears. A dismissed alert is left alone (not re-opened)
while its condition persists.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import timedelta

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.errors import NotFoundError
from app.db.session import set_org_context
from app.models.alert import Alert
from app.models.catalog import Store
from app.models.enums import AlertSeverity, AlertStatus, AlertType
from app.models.inventory import SalesHistory
from app.models.product import Product
from app.schemas.alerts import AlertOut, EvaluateResult
from app.schemas.replenishment import ReplenishmentItem
from app.services import replenishment_service

SLOW_MOVING_DAYS = 30
SEVERITY_RANK = {
    AlertSeverity.CRITICAL: 4,
    AlertSeverity.HIGH: 3,
    AlertSeverity.MEDIUM: 2,
    AlertSeverity.LOW: 1,
}


@dataclass
class Finding:
    alert_type: AlertType
    severity: AlertSeverity
    message: str


def _fmt(value: float) -> str:
    return f"{value:,.0f}" if float(value).is_integer() else f"{value:,.2f}"


def rules(
    item: ReplenishmentItem, *, sold_recently: bool, org_has_recent_sales: bool
) -> list[Finding]:
    found: list[Finding] = []
    on_hand = item.on_hand
    demand = item.avg_daily_demand

    if 0 < on_hand <= item.current_reorder_point:
        severity = (
            AlertSeverity.HIGH if on_hand <= item.current_safety_stock else AlertSeverity.MEDIUM
        )
        found.append(Finding(
            AlertType.LOW_STOCK,
            severity,
            f"On hand {_fmt(on_hand)} is at or below the reorder point "
            f"{_fmt(item.current_reorder_point)}.",
        ))

    if demand > 0 and item.inventory_position < item.lead_time_demand:
        severity = AlertSeverity.CRITICAL if on_hand <= 0 else AlertSeverity.HIGH
        found.append(Finding(
            AlertType.STOCKOUT_RISK,
            severity,
            f"On hand {_fmt(on_hand)} + on order {_fmt(item.on_order)} is below expected "
            f"demand of {_fmt(item.lead_time_demand)} over the {item.lead_time_days}-day "
            "lead time.",
        ))

    threshold = max(60.0, 3.0 * (item.lead_time_days + item.review_days))
    if demand > 0 and item.days_of_cover is not None and item.days_of_cover > threshold:
        severity = (
            AlertSeverity.MEDIUM if item.days_of_cover > 2 * threshold else AlertSeverity.LOW
        )
        found.append(Finding(
            AlertType.OVERSTOCK,
            severity,
            f"{_fmt(item.days_of_cover)} days of cover at {_fmt(demand)}/day "
            f"(threshold {_fmt(threshold)} days).",
        ))

    if on_hand > 0 and org_has_recent_sales and not sold_recently:
        found.append(Finding(
            AlertType.SLOW_MOVING,
            AlertSeverity.LOW,
            f"No sales in the last {SLOW_MOVING_DAYS} days with {_fmt(on_hand)} on hand.",
        ))
    return found


def evaluate(
    db: Session, *, org_id: uuid.UUID, service_level: float = 0.95, review_days: int = 7
) -> EvaluateResult:
    items, history_end = replenishment_service.compute(
        db, org_id=org_id, service_level=service_level, review_days=review_days
    )
    recent: set[tuple[uuid.UUID, uuid.UUID]] = set()
    if history_end is not None:
        since = history_end - timedelta(days=SLOW_MOVING_DAYS - 1)
        recent = {
            (p, s)
            for p, s in db.execute(
                select(SalesHistory.product_id, SalesHistory.store_id)
                .where(
                    SalesHistory.org_id == org_id,
                    SalesHistory.sale_date >= since,
                    SalesHistory.quantity > 0,
                )
                .distinct()
            ).all()
        }
    org_has_recent_sales = bool(recent)

    existing: dict[tuple, Alert] = {}
    for alert in db.execute(
        select(Alert).where(Alert.org_id == org_id, Alert.status != AlertStatus.RESOLVED)
    ).scalars():
        existing[(alert.product_id, alert.store_id, alert.alert_type)] = alert

    created = updated = resolved = 0
    active_keys: set[tuple] = set()
    for item in items:
        findings = rules(
            item,
            sold_recently=(item.product_id, item.store_id) in recent,
            org_has_recent_sales=org_has_recent_sales,
        )
        for finding in findings:
            key = (item.product_id, item.store_id, finding.alert_type)
            active_keys.add(key)
            alert = existing.get(key)
            if alert is None:
                db.add(Alert(
                    id=uuid.uuid4(),
                    org_id=org_id,
                    product_id=item.product_id,
                    store_id=item.store_id,
                    alert_type=finding.alert_type,
                    severity=finding.severity,
                    status=AlertStatus.OPEN,
                    message=finding.message,
                ))
                created += 1
            elif alert.status != AlertStatus.DISMISSED and (
                alert.severity != finding.severity or alert.message != finding.message
            ):
                alert.severity = finding.severity
                alert.message = finding.message
                updated += 1

    for key, alert in existing.items():
        if key not in active_keys and alert.status in (AlertStatus.OPEN, AlertStatus.ACKNOWLEDGED):
            alert.status = AlertStatus.RESOLVED
            resolved += 1
    db.commit()
    open_total = int(
        db.execute(
            select(func.count())
            .select_from(Alert)
            .where(Alert.org_id == org_id, Alert.status == AlertStatus.OPEN)
        ).scalar_one()
    )
    return EvaluateResult(
        created=created,
        updated=updated,
        resolved=resolved,
        open_total=open_total,
        evaluated_items=len(items),
    )


def _out(alert: Alert, product: Product, store: Store) -> AlertOut:
    return AlertOut(
        id=alert.id,
        product_id=alert.product_id,
        store_id=alert.store_id,
        sku=product.sku,
        product_name=product.name,
        store_name=store.name,
        alert_type=alert.alert_type,
        severity=alert.severity,
        status=alert.status,
        message=alert.message,
        created_at=alert.created_at,
        updated_at=alert.updated_at,
    )


def list_alerts(
    db: Session,
    *,
    org_id: uuid.UUID,
    limit: int,
    offset: int,
    status: AlertStatus | None = None,
    alert_type: AlertType | None = None,
    severity: AlertSeverity | None = None,
    store_id: uuid.UUID | None = None,
) -> tuple[list[AlertOut], int]:
    set_org_context(db, org_id)
    filters = [Alert.org_id == org_id]
    if status is not None:
        filters.append(Alert.status == status)
    if alert_type is not None:
        filters.append(Alert.alert_type == alert_type)
    if severity is not None:
        filters.append(Alert.severity == severity)
    if store_id is not None:
        filters.append(Alert.store_id == store_id)
    rows = db.execute(
        select(Alert, Product, Store)
        .join(Product, Product.id == Alert.product_id)
        .join(Store, Store.id == Alert.store_id)
        .where(*filters)
    ).all()
    # Most severe first, then newest; done in Python because severity is a
    # string enum whose alphabetical order is meaningless.
    rows.sort(
        key=lambda r: (-SEVERITY_RANK[r[0].severity], -r[0].created_at.timestamp(), r[1].sku)
    )
    page = rows[offset : offset + limit]
    return [_out(a, p, s) for a, p, s in page], len(rows)


def update_status(
    db: Session, *, org_id: uuid.UUID, alert_id: uuid.UUID, status: AlertStatus
) -> AlertOut:
    set_org_context(db, org_id)
    alert = db.get(Alert, alert_id)
    if alert is None or alert.org_id != org_id:
        raise NotFoundError("Alert not found.")
    alert.status = status
    db.commit()
    db.refresh(alert)
    product = db.get(Product, alert.product_id)
    store = db.get(Store, alert.store_id)
    assert product is not None and store is not None
    return _out(alert, product, store)


def open_count(db: Session, *, org_id: uuid.UUID) -> int:
    return int(
        db.execute(
            select(func.count())
            .select_from(Alert)
            .where(Alert.org_id == org_id, Alert.status == AlertStatus.OPEN)
        ).scalar_one()
    )
