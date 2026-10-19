"""Turn stored sales history into daily, zero-filled time series."""

from __future__ import annotations

import uuid
from datetime import date

import pandas as pd
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.inventory import SalesHistory

SeriesKey = tuple[uuid.UUID, uuid.UUID]  # (product_id, store_id)


def load_daily_series(
    db: Session, *, org_id: uuid.UUID
) -> tuple[dict[SeriesKey, pd.Series], date | None, date | None]:
    """Return one daily series per product/store plus the dataset date range.

    Each series runs from its first recorded sale to the organisation's last
    sales date; days without a row are zero (no recorded sales).
    """
    rows = db.execute(
        select(
            SalesHistory.product_id,
            SalesHistory.store_id,
            SalesHistory.sale_date,
            SalesHistory.quantity,
        ).where(SalesHistory.org_id == org_id)
    ).all()
    if not rows:
        return {}, None, None

    frame = pd.DataFrame(rows, columns=["product_id", "store_id", "sale_date", "quantity"])
    frame["sale_date"] = pd.to_datetime(frame["sale_date"])
    frame["quantity"] = frame["quantity"].astype(float)
    start = frame["sale_date"].min()
    end = frame["sale_date"].max()

    series: dict[SeriesKey, pd.Series] = {}
    for (product_id, store_id), group in frame.groupby(["product_id", "store_id"], sort=True):
        daily = group.groupby("sale_date")["quantity"].sum()
        index = pd.date_range(daily.index.min(), end, freq="D")
        series[(product_id, store_id)] = daily.reindex(index, fill_value=0.0).astype(float)
    return series, start.date(), end.date()
