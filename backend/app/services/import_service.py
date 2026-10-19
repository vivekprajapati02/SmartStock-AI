"""Sales-history CSV import: parse, validate, de-duplicate, persist.

Every upload produces an ``import_batches`` audit row with exact counts and a
per-row error report. Valid rows are inserted in the same transaction as the
batch record, so a batch either lands with all of its valid rows or not at all.
Invalid and duplicate rows are reported, never silently dropped.
"""

from __future__ import annotations

import csv
import io
import uuid
from dataclasses import dataclass, field
from datetime import UTC, date, datetime
from decimal import Decimal

from pydantic import ValidationError
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.errors import NotFoundError
from app.core.logging import get_logger
from app.db.session import set_org_context
from app.models.catalog import Store
from app.models.enums import ImportStatus
from app.models.imports import ImportBatch
from app.models.inventory import SalesHistory
from app.models.product import Product
from app.schemas.imports import REQUIRED_COLUMNS, ImportRowError, SalesRowIn

logger = get_logger(__name__)

MAX_FILE_BYTES = 5 * 1024 * 1024
MAX_ROWS = 50_000
# Counts are always exact; only the stored detail list is capped.
MAX_STORED_ERRORS = 1_000

SalesKey = tuple[uuid.UUID, uuid.UUID, date]


@dataclass
class ImportResult:
    total_rows: int = 0
    valid: list[tuple[SalesKey, Decimal]] = field(default_factory=list)
    invalid_rows: int = 0
    duplicate_rows: int = 0
    errors: list[ImportRowError] = field(default_factory=list)
    file_error: bool = False

    def add_error(self, error: ImportRowError) -> None:
        if len(self.errors) < MAX_STORED_ERRORS:
            self.errors.append(error)


def _file_failure(message: str) -> ImportResult:
    result = ImportResult(file_error=True)
    result.add_error(ImportRowError(message=message, kind="file"))
    return result


def _decode(content: bytes) -> str | None:
    try:
        # utf-8-sig strips the BOM Excel adds when saving "CSV UTF-8".
        return content.decode("utf-8-sig")
    except UnicodeDecodeError:
        return None


def _status(result: ImportResult) -> ImportStatus:
    if result.file_error or not result.valid:
        return ImportStatus.FAILED
    if result.invalid_rows or result.duplicate_rows:
        return ImportStatus.PARTIAL
    return ImportStatus.COMPLETED


def parse_sales_csv(
    db: Session,
    *,
    org_id: uuid.UUID,
    content: bytes,
) -> ImportResult:
    """Validate a sales CSV against the organisation's catalogue and history."""
    if len(content) > MAX_FILE_BYTES:
        return _file_failure(
            f"File is larger than the {MAX_FILE_BYTES // (1024 * 1024)} MB limit."
        )
    text = _decode(content)
    if text is None:
        return _file_failure("File is not valid UTF-8 text. Save it as 'CSV UTF-8'.")
    if not text.strip():
        return _file_failure("File is empty.")

    reader = csv.reader(io.StringIO(text, newline=""))
    try:
        header = next(reader)
    except (StopIteration, csv.Error):
        return _file_failure("Could not read a header row.")

    columns = [h.strip().lower() for h in header]
    missing = [c for c in REQUIRED_COLUMNS if c not in columns]
    if missing:
        return _file_failure(
            "Missing required column(s): "
            + ", ".join(missing)
            + ". Expected header: "
            + ",".join(REQUIRED_COLUMNS)
            + "."
        )
    duplicated_headers = sorted({c for c in columns if c and columns.count(c) > 1})
    if duplicated_headers:
        return _file_failure("Duplicate column(s): " + ", ".join(duplicated_headers) + ".")
    index = {name: columns.index(name) for name in REQUIRED_COLUMNS}

    products = {
        sku: pid
        for pid, sku in db.execute(
            select(Product.id, Product.sku).where(Product.org_id == org_id)
        ).all()
    }
    stores = {
        name.strip().lower(): sid
        for sid, name in db.execute(
            select(Store.id, Store.name).where(Store.org_id == org_id)
        ).all()
    }

    result = ImportResult()
    candidates: list[tuple[int, SalesKey, Decimal]] = []
    try:
        for row_number, raw in enumerate(reader, start=1):
            if not any(cell.strip() for cell in raw):
                continue  # Blank lines are not data rows.
            result.total_rows += 1
            if result.total_rows > MAX_ROWS:
                return _file_failure(f"File has more than {MAX_ROWS:,} data rows.")
            if len(raw) > len(columns):
                result.invalid_rows += 1
                result.add_error(ImportRowError(
                    row=row_number,
                    message=f"Row has {len(raw)} values but the header has {len(columns)}.",
                ))
                continue
            values = {name: (raw[i] if i < len(raw) else "") for name, i in index.items()}
            try:
                parsed = SalesRowIn.model_validate(values)
            except ValidationError as exc:
                result.invalid_rows += 1
                first = exc.errors()[0]
                column = str(first["loc"][0]) if first.get("loc") else None
                result.add_error(ImportRowError(
                    row=row_number,
                    column=column,
                    value=values.get(column) if column else None,
                    message=str(first["msg"]).removeprefix("Value error, "),
                ))
                continue

            product_id = products.get(parsed.sku)
            if product_id is None:
                result.invalid_rows += 1
                result.add_error(ImportRowError(
                    row=row_number, column="sku", value=parsed.sku,
                    message="Unknown SKU for this organisation.",
                ))
                continue
            store_id = stores.get(parsed.store.lower())
            if store_id is None:
                result.invalid_rows += 1
                result.add_error(ImportRowError(
                    row=row_number, column="store", value=parsed.store,
                    message="Unknown store name for this organisation.",
                ))
                continue
            candidates.append(
                (row_number, (product_id, store_id, parsed.sale_date), parsed.quantity)
            )
    except csv.Error as exc:
        return _file_failure(f"Malformed CSV: {exc}.")

    existing = _existing_keys(db, org_id=org_id, keys=[c[1] for c in candidates])
    seen: dict[SalesKey, int] = {}
    for row_number, key, quantity in candidates:
        if key in existing:
            result.duplicate_rows += 1
            result.add_error(ImportRowError(
                row=row_number, column="sale_date", value=key[2].isoformat(), kind="duplicate",
                message="Sales for this SKU, store and date already exist.",
            ))
        elif key in seen:
            result.duplicate_rows += 1
            result.add_error(ImportRowError(
                row=row_number, column="sale_date", value=key[2].isoformat(), kind="duplicate",
                message=f"Same SKU, store and date as row {seen[key]} in this file.",
            ))
        else:
            seen[key] = row_number
            result.valid.append((key, quantity))

    if result.total_rows == 0:
        return _file_failure("File has a header but no data rows.")
    return result


def _existing_keys(
    db: Session, *, org_id: uuid.UUID, keys: list[SalesKey]
) -> set[SalesKey]:
    if not keys:
        return set()
    product_ids = {k[0] for k in keys}
    dates = [k[2] for k in keys]
    rows = db.execute(
        select(SalesHistory.product_id, SalesHistory.store_id, SalesHistory.sale_date).where(
            SalesHistory.org_id == org_id,
            SalesHistory.product_id.in_(product_ids),
            SalesHistory.sale_date >= min(dates),
            SalesHistory.sale_date <= max(dates),
        )
    ).all()
    return {(p, s, d) for p, s, d in rows}


def import_sales_csv(
    db: Session,
    *,
    org_id: uuid.UUID,
    filename: str,
    content: bytes,
) -> ImportBatch:
    """Validate the CSV and persist the batch plus its valid rows atomically."""
    set_org_context(db, org_id)
    result = parse_sales_csv(db, org_id=org_id, content=content)

    batch = ImportBatch(
        id=uuid.uuid4(),
        org_id=org_id,
        filename=(filename or "upload.csv")[:255],
        status=_status(result),
        total_rows=result.total_rows,
        valid_rows=len(result.valid),
        invalid_rows=result.invalid_rows,
        duplicate_rows=result.duplicate_rows,
        errors=[e.model_dump() for e in result.errors],
        # Python-side timestamp keeps the history list ordered within a second.
        created_at=datetime.now(UTC),
    )
    db.add(batch)
    db.add_all(
        SalesHistory(
            org_id=org_id,
            product_id=product_id,
            store_id=store_id,
            sale_date=sale_date,
            quantity=quantity,
        )
        for (product_id, store_id, sale_date), quantity in result.valid
    )
    try:
        db.commit()
    except IntegrityError:
        # A concurrent import inserted overlapping rows after validation. Roll
        # back every row and record the batch as failed so nothing is partial.
        db.rollback()
        logger.warning("Import %s conflicted with concurrent writes", batch.id)
        set_org_context(db, org_id)
        batch = ImportBatch(
            id=uuid.uuid4(),
            org_id=org_id,
            filename=(filename or "upload.csv")[:255],
            created_at=datetime.now(UTC),
            status=ImportStatus.FAILED,
            total_rows=result.total_rows,
            valid_rows=0,
            invalid_rows=result.invalid_rows,
            duplicate_rows=result.duplicate_rows,
            errors=[
                ImportRowError(
                    kind="file",
                    message="Another import changed the same sales rows at the same time. "
                    "No rows were saved; upload the file again.",
                ).model_dump(),
                *(e.model_dump() for e in result.errors),
            ][:MAX_STORED_ERRORS],
        )
        db.add(batch)
        db.commit()
    db.refresh(batch)
    return batch


def list_batches(
    db: Session, *, org_id: uuid.UUID, limit: int, offset: int
) -> tuple[list[ImportBatch], int]:
    set_org_context(db, org_id)
    total = int(
        db.execute(
            select(func.count()).select_from(ImportBatch).where(ImportBatch.org_id == org_id)
        ).scalar_one()
    )
    items = (
        db.execute(
            select(ImportBatch)
            .where(ImportBatch.org_id == org_id)
            .order_by(ImportBatch.created_at.desc(), ImportBatch.id.desc())
            .limit(limit)
            .offset(offset)
        )
        .scalars()
        .all()
    )
    return list(items), total


def get_batch(db: Session, *, org_id: uuid.UUID, batch_id: uuid.UUID) -> ImportBatch:
    set_org_context(db, org_id)
    batch = db.get(ImportBatch, batch_id)
    if batch is None or batch.org_id != org_id:
        raise NotFoundError("Import not found.")
    return batch
