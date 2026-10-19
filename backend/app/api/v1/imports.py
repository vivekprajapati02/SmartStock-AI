"""Sales-history CSV import endpoints."""

from __future__ import annotations

import csv
import io
import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, File, Query, UploadFile, status
from fastapi.responses import Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser, require_roles
from app.core.rbac import Role
from app.db.session import get_db, set_org_context
from app.models.catalog import Store
from app.models.imports import ImportBatch
from app.models.product import Product
from app.models.user import User
from app.schemas.common import Page
from app.schemas.imports import (
    REQUIRED_COLUMNS,
    ImportBatchDetail,
    ImportBatchOut,
    ImportRowError,
)
from app.services import import_service

router = APIRouter(prefix="/imports", tags=["imports"])
ManagerUser = Annotated[User, Depends(require_roles(Role.OWNER, Role.ADMIN, Role.MANAGER))]


def _error_count(batch: ImportBatch) -> int:
    file_errors = sum(1 for e in batch.errors or [] if e.get("kind") == "file")
    return batch.invalid_rows + batch.duplicate_rows + file_errors


def _to_out(batch: ImportBatch) -> ImportBatchOut:
    return ImportBatchOut(
        id=batch.id,
        org_id=batch.org_id,
        filename=batch.filename,
        status=batch.status,
        total_rows=batch.total_rows,
        valid_rows=batch.valid_rows,
        invalid_rows=batch.invalid_rows,
        duplicate_rows=batch.duplicate_rows,
        error_count=_error_count(batch),
        created_at=batch.created_at,
    )


def _to_detail(batch: ImportBatch) -> ImportBatchDetail:
    errors = [ImportRowError.model_validate(e) for e in batch.errors or []]
    out = _to_out(batch)
    return ImportBatchDetail(
        **out.model_dump(),
        errors=errors,
        errors_truncated=out.error_count > len(errors),
    )


@router.post("", response_model=ImportBatchDetail, status_code=status.HTTP_201_CREATED)
def upload_sales_csv(
    user: ManagerUser,
    db: Annotated[Session, Depends(get_db)],
    file: Annotated[UploadFile, File(description="Sales CSV: sku,store,sale_date,quantity")],
) -> ImportBatchDetail:
    """Import daily sales. Always records a batch; inspect ``status`` and
    ``errors`` for rows that were rejected."""
    # Read one byte past the limit so oversize files are detected, not truncated.
    content = file.file.read(import_service.MAX_FILE_BYTES + 1)
    batch = import_service.import_sales_csv(
        db, org_id=user.org_id, filename=file.filename or "upload.csv", content=content
    )
    return _to_detail(batch)


@router.get("", response_model=Page[ImportBatchOut])
def list_imports(
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> Page[ImportBatchOut]:
    items, total = import_service.list_batches(
        db, org_id=user.org_id, limit=limit, offset=offset
    )
    return Page[ImportBatchOut](
        items=[_to_out(b) for b in items], total=total, limit=limit, offset=offset
    )


@router.get("/template", response_class=Response)
def download_template(
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> Response:
    """A CSV header plus one example row using this organisation's own SKU and
    store (quantity left as 0 so nothing is invented)."""
    set_org_context(db, user.org_id)
    sku = db.execute(
        select(Product.sku).where(Product.org_id == user.org_id).order_by(Product.sku).limit(1)
    ).scalar_one_or_none()
    store = db.execute(
        select(Store.name).where(Store.org_id == user.org_id).order_by(Store.name).limit(1)
    ).scalar_one_or_none()
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(REQUIRED_COLUMNS)
    if sku and store:
        writer.writerow([sku, store, date.today().isoformat(), "0"])
    return Response(
        content=buffer.getvalue(),
        media_type="text/csv",
        headers={"Content-Disposition": 'attachment; filename="sales_import_template.csv"'},
    )


@router.get("/{batch_id}", response_model=ImportBatchDetail)
def get_import(
    batch_id: uuid.UUID,
    user: CurrentUser,
    db: Annotated[Session, Depends(get_db)],
) -> ImportBatchDetail:
    return _to_detail(import_service.get_batch(db, org_id=user.org_id, batch_id=batch_id))
