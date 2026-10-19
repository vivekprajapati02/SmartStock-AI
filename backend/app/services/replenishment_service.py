"""Reorder point, safety stock, target stock and order quantity per SKU/store.

Daily demand is estimated from the most recent ``history_days`` of stored
sales (zero-filled). When a stored forecast covers ``lead time + review
period``, its daily values replace the historical mean for the lead-time and
target calculations; the standard deviation always comes from history.

    safety_stock   = z * sigma_daily * sqrt(lead_time)
    reorder_point  = demand over lead time + safety_stock
    target_stock   = demand over (lead time + review period) + safety_stock
    position       = on hand + on order (open purchase orders)
    recommended    = ceil(target_stock - position) if position <= reorder_point else 0
"""

from __future__ import annotations

import math
import uuid
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, timedelta
from decimal import Decimal
from statistics import NormalDist

import numpy as np
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db.session import set_org_context
from app.models.catalog import Store, Supplier
from app.models.enums import PurchaseOrderStatus
from app.models.forecasting import Forecast, ModelRun
from app.models.inventory import Inventory, SalesHistory
from app.models.product import Product
from app.models.purchasing import PurchaseOrder, PurchaseOrderItem
from app.schemas.replenishment import ReplenishmentItem

OPEN_PO_STATUSES = (
    PurchaseOrderStatus.PENDING,
    PurchaseOrderStatus.APPROVED,
    PurchaseOrderStatus.PARTIAL,
)
Key = tuple[uuid.UUID, uuid.UUID]


def z_for(service_level: float) -> float:
    return NormalDist().inv_cdf(service_level)


@dataclass
class _Context:
    history_end: date | None
    history_days: int
    sales: dict[Key, np.ndarray]
    forecasts: dict[int, tuple[str, dict[Key, list[float]]]]  # horizon -> (model, values)
    on_order: dict[Key, float]


def _load_context(db: Session, *, org_id: uuid.UUID, history_days: int) -> _Context:
    end = db.execute(
        select(func.max(SalesHistory.sale_date)).where(SalesHistory.org_id == org_id)
    ).scalar_one()
    sales: dict[Key, np.ndarray] = {}
    if end is not None:
        start = end - timedelta(days=history_days - 1)
        buckets: dict[Key, np.ndarray] = defaultdict(lambda: np.zeros(history_days))
        for product_id, store_id, day, qty in db.execute(
            select(
                SalesHistory.product_id,
                SalesHistory.store_id,
                SalesHistory.sale_date,
                SalesHistory.quantity,
            ).where(
                SalesHistory.org_id == org_id,
                SalesHistory.sale_date >= start,
                SalesHistory.sale_date <= end,
            )
        ).all():
            buckets[(product_id, store_id)][(day - start).days] += float(qty)
        sales = dict(buckets)

    forecasts: dict[int, tuple[str, dict[Key, list[float]]]] = {}
    runs = (
        db.execute(
            select(ModelRun)
            .where(ModelRun.org_id == org_id)
            .order_by(ModelRun.trained_at.desc())
        )
        .scalars()
        .all()
    )
    for run in runs:
        if (run.params or {}).get("kind") != "forecast" or run.horizon in forecasts:
            continue
        values: dict[Key, list[float]] = defaultdict(list)
        for product_id, store_id, qty in db.execute(
            select(Forecast.product_id, Forecast.store_id, Forecast.y_pred)
            .where(Forecast.org_id == org_id, Forecast.model_run_id == run.id)
            .order_by(Forecast.forecast_date)
        ).all():
            values[(product_id, store_id)].append(float(qty))
        forecasts[run.horizon] = (run.model_name, dict(values))

    on_order: dict[Key, float] = defaultdict(float)
    for product_id, store_id, ordered, received in db.execute(
        select(
            PurchaseOrderItem.product_id,
            PurchaseOrder.store_id,
            PurchaseOrderItem.quantity_ordered,
            PurchaseOrderItem.quantity_received,
        )
        .join(PurchaseOrder, PurchaseOrder.id == PurchaseOrderItem.purchase_order_id)
        .where(
            PurchaseOrder.org_id == org_id,
            PurchaseOrder.status.in_(OPEN_PO_STATUSES),
        )
    ).all():
        on_order[(product_id, store_id)] += max(0.0, float(ordered) - float(received))
    return _Context(end, history_days, sales, forecasts, dict(on_order))


def _r(value: float) -> float:
    return round(float(value), 3)


def _recommend(
    inventory: Inventory,
    product: Product,
    store: Store,
    supplier: Supplier | None,
    ctx: _Context,
    *,
    z: float,
    review_days: int,
) -> ReplenishmentItem:
    key = (inventory.product_id, inventory.store_id)
    lead = int(inventory.lead_time_days)
    on_hand = float(inventory.quantity_on_hand)
    on_order = ctx.on_order.get(key, 0.0)
    position = on_hand + on_order

    if ctx.history_end is None:
        history = np.zeros(1)
        source = "none"
    else:
        history = ctx.sales.get(key, np.zeros(ctx.history_days))
        source = "history"
    mean = float(history.mean())
    std = float(history.std(ddof=1)) if len(history) > 1 else 0.0

    needed = lead + review_days
    lead_demand = mean * lead
    cycle_demand = mean * needed
    model_name = None
    for horizon in sorted(ctx.forecasts):
        if horizon < needed:
            continue
        name, values = ctx.forecasts[horizon]
        series = values.get(key)
        if series and len(series) >= needed:
            lead_demand = float(sum(series[:lead]))
            cycle_demand = float(sum(series[:needed]))
            source, model_name = "forecast", name
            break

    safety = z * std * math.sqrt(lead)
    reorder_point = lead_demand + safety
    target = cycle_demand + safety
    recommended = 0.0
    if position <= reorder_point and target - position > 0:
        recommended = float(math.ceil(target - position - 1e-9))
    daily = cycle_demand / needed if needed else mean
    return ReplenishmentItem(
        inventory_id=inventory.id,
        product_id=inventory.product_id,
        store_id=inventory.store_id,
        sku=product.sku,
        product_name=product.name,
        store_name=store.name,
        supplier_id=supplier.id if supplier else None,
        supplier_name=supplier.name if supplier else None,
        on_hand=_r(on_hand),
        on_order=_r(on_order),
        inventory_position=_r(position),
        lead_time_days=lead,
        review_days=review_days,
        avg_daily_demand=_r(daily),
        demand_std=_r(std),
        demand_source=source,
        forecast_model=model_name,
        lead_time_demand=_r(lead_demand),
        safety_stock=_r(safety),
        reorder_point=_r(reorder_point),
        target_stock=_r(target),
        recommended_qty=_r(recommended),
        days_of_cover=_r(on_hand / daily) if daily > 0 else None,
        needs_reorder=recommended > 0,
        current_reorder_point=_r(float(inventory.reorder_point)),
        current_safety_stock=_r(float(inventory.safety_stock)),
    )


def compute(
    db: Session,
    *,
    org_id: uuid.UUID,
    service_level: float = 0.95,
    review_days: int = 7,
    history_days: int = 56,
    store_id: uuid.UUID | None = None,
    inventory_ids: list[uuid.UUID] | None = None,
) -> tuple[list[ReplenishmentItem], date | None]:
    set_org_context(db, org_id)
    ctx = _load_context(db, org_id=org_id, history_days=history_days)
    z = z_for(service_level)
    query = (
        select(Inventory, Product, Store, Supplier)
        .join(Product, Product.id == Inventory.product_id)
        .join(Store, Store.id == Inventory.store_id)
        .outerjoin(Supplier, Supplier.id == Product.supplier_id)
        .where(Inventory.org_id == org_id)
        .order_by(Product.sku, Store.name)
    )
    if store_id is not None:
        query = query.where(Inventory.store_id == store_id)
    if inventory_ids is not None:
        query = query.where(Inventory.id.in_(inventory_ids))
    rows = db.execute(query).all()
    items = [
        _recommend(inv, product, store, supplier, ctx, z=z, review_days=review_days)
        for inv, product, store, supplier in rows
    ]
    return items, ctx.history_end


def apply(
    db: Session,
    *,
    org_id: uuid.UUID,
    service_level: float,
    review_days: int,
    store_id: uuid.UUID | None,
    inventory_ids: list[uuid.UUID] | None,
) -> int:
    """Store the computed reorder point and safety stock on inventory rows."""
    items, _ = compute(
        db,
        org_id=org_id,
        service_level=service_level,
        review_days=review_days,
        store_id=store_id,
        inventory_ids=inventory_ids,
    )
    by_id = {item.inventory_id: item for item in items}
    if not by_id:
        return 0
    rows = (
        db.execute(
            select(Inventory).where(Inventory.org_id == org_id, Inventory.id.in_(list(by_id)))
        )
        .scalars()
        .all()
    )
    for row in rows:
        item = by_id[row.id]
        row.reorder_point = Decimal(str(item.reorder_point))
        row.safety_stock = Decimal(str(item.safety_stock))
    db.commit()
    return len(rows)
