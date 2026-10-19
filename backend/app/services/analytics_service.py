"""Dashboard metrics computed from stored data. No hardcoded values."""

from __future__ import annotations

import uuid
from datetime import date, timedelta
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db.session import set_org_context
from app.models.catalog import Store
from app.models.enums import PurchaseOrderStatus
from app.models.inventory import Inventory, SalesHistory
from app.models.organization import Organization
from app.models.product import Product
from app.models.purchasing import PurchaseOrder
from app.schemas.analytics import DashboardOut, DemandPoint


def get_dashboard(db: Session, *, org_id: uuid.UUID, trend_days: int = 30) -> DashboardOut:
    set_org_context(db, org_id)

    org = db.get(Organization, org_id)
    is_demo = bool(org.is_demo) if org is not None else False

    inventory_value = db.execute(
        select(func.coalesce(func.sum(Inventory.quantity_on_hand * Product.unit_cost), 0)).join(
            Product, Product.id == Inventory.product_id
        ).where(Inventory.org_id == org_id)
    ).scalar_one()

    sku_count = int(
        db.execute(
            select(func.count()).select_from(Product).where(Product.org_id == org_id)
        ).scalar_one()
    )
    store_count = int(
        db.execute(
            select(func.count()).select_from(Store).where(Store.org_id == org_id)
        ).scalar_one()
    )
    low_stock_count = int(
        db.execute(
            select(func.count())
            .select_from(Inventory)
            .where(
                Inventory.org_id == org_id,
                Inventory.quantity_on_hand <= Inventory.reorder_point,
                Inventory.quantity_on_hand > 0,
            )
        ).scalar_one()
    )
    stockout_count = int(
        db.execute(
            select(func.count())
            .select_from(Inventory)
            .where(Inventory.org_id == org_id, Inventory.quantity_on_hand <= 0)
        ).scalar_one()
    )
    pending_order_count = int(
        db.execute(
            select(func.count())
            .select_from(PurchaseOrder)
            .where(
                PurchaseOrder.org_id == org_id,
                PurchaseOrder.status.in_(
                    (
                        PurchaseOrderStatus.PENDING,
                        PurchaseOrderStatus.APPROVED,
                        PurchaseOrderStatus.PARTIAL,
                    )
                ),
            )
        ).scalar_one()
    )

    end = date.today()
    start = end - timedelta(days=trend_days - 1)
    rows = db.execute(
        select(SalesHistory.sale_date, func.coalesce(func.sum(SalesHistory.quantity), 0))
        .where(
            SalesHistory.org_id == org_id,
            SalesHistory.sale_date >= start,
            SalesHistory.sale_date <= end,
        )
        .group_by(SalesHistory.sale_date)
        .order_by(SalesHistory.sale_date)
    ).all()
    by_date = {row[0]: Decimal(row[1]) for row in rows}
    demand_trend = []
    for i in range(trend_days):
        day = start + timedelta(days=i)
        demand_trend.append(DemandPoint(sale_date=day, quantity=by_date.get(day, Decimal("0"))))

    return DashboardOut(
        inventory_value=Decimal(inventory_value),
        sku_count=sku_count,
        store_count=store_count,
        low_stock_count=low_stock_count,
        stockout_count=stockout_count,
        pending_order_count=pending_order_count,
        demand_trend=demand_trend,
        is_demo=is_demo,
    )
