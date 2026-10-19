"""Purchase order lifecycle with transactional (partial) receipts.

    draft --submit--> pending --approve--> approved --receive--> partial --> received
      \\________________cancel (draft/pending/approved)________________/

Receiving writes one ``in`` stock movement per line, increases on-hand stock
and updates line/order status in a single transaction: any invalid line
(unknown, over-receipt, wrong status) rejects the whole receipt.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import date
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.errors import ConflictError, NotFoundError, UnprocessableError
from app.db.session import set_org_context
from app.models.catalog import Store, Supplier
from app.models.enums import MovementType, PurchaseOrderStatus
from app.models.product import Product
from app.models.purchasing import PurchaseOrder, PurchaseOrderItem
from app.schemas.purchasing import (
    FromRecommendationsResult,
    PODetail,
    POItemIn,
    POItemOut,
    POOut,
    ReceiveLine,
    SkippedItem,
)
from app.services import inventory_service, replenishment_service

S = PurchaseOrderStatus
ZERO = Decimal("0")


def _require(db: Session, model, obj_id: uuid.UUID, org_id: uuid.UUID, label: str):
    obj = db.get(model, obj_id)
    if obj is None or obj.org_id != org_id:
        raise NotFoundError(f"{label} not found.")
    return obj


def _get_po(
    db: Session, org_id: uuid.UUID, po_id: uuid.UUID, *, lock: bool = False
) -> PurchaseOrder:
    set_org_context(db, org_id)
    query = select(PurchaseOrder).where(PurchaseOrder.id == po_id, PurchaseOrder.org_id == org_id)
    if lock:
        query = query.with_for_update()
    po = db.execute(query).scalar_one_or_none()
    if po is None:
        raise NotFoundError("Purchase order not found.")
    return po


def _items(db: Session, po: PurchaseOrder) -> list[tuple[PurchaseOrderItem, Product]]:
    return list(
        db.execute(
            select(PurchaseOrderItem, Product)
            .join(Product, Product.id == PurchaseOrderItem.product_id)
            .where(PurchaseOrderItem.purchase_order_id == po.id)
            .order_by(Product.sku)
        ).all()
    )


def _summary(db: Session, po: PurchaseOrder, items=None) -> POOut:
    rows = items if items is not None else _items(db, po)
    supplier = db.get(Supplier, po.supplier_id)
    store = db.get(Store, po.store_id)
    return POOut(
        id=po.id,
        org_id=po.org_id,
        supplier_id=po.supplier_id,
        supplier_name=supplier.name if supplier else None,
        store_id=po.store_id,
        store_name=store.name if store else None,
        status=po.status,
        reference=po.reference,
        expected_date=po.expected_date,
        created_by=po.created_by,
        approved_by=po.approved_by,
        line_count=len(rows),
        total_ordered=sum((i.quantity_ordered for i, _ in rows), ZERO),
        total_received=sum((i.quantity_received for i, _ in rows), ZERO),
        estimated_cost=sum((i.quantity_ordered * p.unit_cost for i, p in rows), ZERO),
        created_at=po.created_at,
        updated_at=po.updated_at,
    )


def detail(db: Session, po: PurchaseOrder) -> PODetail:
    rows = _items(db, po)
    return PODetail(
        **_summary(db, po, rows).model_dump(),
        items=[
            POItemOut(
                id=i.id,
                product_id=i.product_id,
                sku=p.sku,
                product_name=p.name,
                unit_cost=p.unit_cost,
                quantity_ordered=i.quantity_ordered,
                quantity_received=i.quantity_received,
                quantity_remaining=i.quantity_ordered - i.quantity_received,
            )
            for i, p in rows
        ],
    )


def _set_items(db: Session, po: PurchaseOrder, items: list[POItemIn]) -> None:
    for line in items:
        _require(db, Product, line.product_id, po.org_id, "Product")
    # Go through the relationship so the loaded collection stays consistent
    # (delete-orphan removes replaced lines).
    po.items.clear()
    db.flush()
    for line in items:
        po.items.append(PurchaseOrderItem(
            id=uuid.uuid4(),
            org_id=po.org_id,
            product_id=line.product_id,
            quantity_ordered=line.quantity_ordered,
            quantity_received=ZERO,
        ))
    db.flush()


def create(
    db: Session,
    *,
    org_id: uuid.UUID,
    user_id: uuid.UUID,
    supplier_id: uuid.UUID,
    store_id: uuid.UUID,
    reference: str | None,
    expected_date: date | None,
    items: list[POItemIn],
    commit: bool = True,
) -> PurchaseOrder:
    set_org_context(db, org_id)
    _require(db, Supplier, supplier_id, org_id, "Supplier")
    _require(db, Store, store_id, org_id, "Store")
    po = PurchaseOrder(
        id=uuid.uuid4(),
        org_id=org_id,
        supplier_id=supplier_id,
        store_id=store_id,
        status=S.DRAFT,
        reference=reference,
        expected_date=expected_date,
        created_by=user_id,
    )
    db.add(po)
    db.flush()
    _set_items(db, po, items)
    if commit:
        db.commit()
        db.refresh(po)
    return po


def update(
    db: Session,
    *,
    org_id: uuid.UUID,
    po_id: uuid.UUID,
    fields: dict,
) -> PurchaseOrder:
    po = _get_po(db, org_id, po_id, lock=True)
    if po.status != S.DRAFT:
        raise ConflictError("Only draft purchase orders can be edited.")
    if "reference" in fields:
        po.reference = fields["reference"]
    if "expected_date" in fields:
        po.expected_date = fields["expected_date"]
    if fields.get("items") is not None:
        _set_items(db, po, [POItemIn.model_validate(i) for i in fields["items"]])
    db.commit()
    db.refresh(po)
    return po


_TRANSITIONS = {
    "submit": ({S.DRAFT}, S.PENDING),
    "approve": ({S.PENDING}, S.APPROVED),
    "cancel": ({S.DRAFT, S.PENDING, S.APPROVED}, S.CANCELLED),
}


def transition(
    db: Session, *, org_id: uuid.UUID, po_id: uuid.UUID, action: str, user_id: uuid.UUID
) -> PurchaseOrder:
    allowed, target = _TRANSITIONS[action]
    po = _get_po(db, org_id, po_id, lock=True)
    if po.status not in allowed:
        raise ConflictError(
            f"Cannot {action} a purchase order that is {po.status.value}."
        )
    if action == "submit" and not po.items:
        raise UnprocessableError("Add at least one line before submitting.")
    po.status = target
    if action == "approve":
        po.approved_by = user_id
    db.commit()
    db.refresh(po)
    return po


def receive(
    db: Session,
    *,
    org_id: uuid.UUID,
    po_id: uuid.UUID,
    lines: list[ReceiveLine],
    note: str | None,
) -> PurchaseOrder:
    po = _get_po(db, org_id, po_id, lock=True)
    if po.status not in (S.APPROVED, S.PARTIAL):
        raise ConflictError(
            f"Only approved or partially received orders can be received (status: "
            f"{po.status.value})."
        )
    items = {item.id: item for item in po.items}
    reference = po.reference or f"PO-{str(po.id)[:8]}"
    try:
        for line in lines:
            item = items.get(line.item_id)
            if item is None:
                raise UnprocessableError("Receipt line does not belong to this purchase order.")
            remaining = item.quantity_ordered - item.quantity_received
            if line.quantity > remaining:
                raise UnprocessableError(
                    f"Cannot receive {line.quantity} - only {remaining} remaining on this line."
                )
            inventory_service.apply_movement(
                db,
                org_id=org_id,
                product_id=item.product_id,
                store_id=po.store_id,
                movement_type=MovementType.IN,
                quantity=line.quantity,
                reference=reference,
                note=note or "Purchase order receipt",
            )
            item.quantity_received = item.quantity_received + line.quantity
        fully = all(i.quantity_received >= i.quantity_ordered for i in po.items)
        po.status = S.RECEIVED if fully else S.PARTIAL
        db.commit()
    except Exception:
        db.rollback()
        raise
    db.refresh(po)
    return po


def list_orders(
    db: Session,
    *,
    org_id: uuid.UUID,
    limit: int,
    offset: int,
    status: PurchaseOrderStatus | None = None,
    supplier_id: uuid.UUID | None = None,
    store_id: uuid.UUID | None = None,
) -> tuple[list[POOut], int]:
    set_org_context(db, org_id)
    filters = [PurchaseOrder.org_id == org_id]
    if status is not None:
        filters.append(PurchaseOrder.status == status)
    if supplier_id is not None:
        filters.append(PurchaseOrder.supplier_id == supplier_id)
    if store_id is not None:
        filters.append(PurchaseOrder.store_id == store_id)
    total = int(
        db.execute(select(func.count()).select_from(PurchaseOrder).where(*filters)).scalar_one()
    )
    orders = (
        db.execute(
            select(PurchaseOrder)
            .where(*filters)
            .order_by(PurchaseOrder.created_at.desc(), PurchaseOrder.id.desc())
            .limit(limit)
            .offset(offset)
        )
        .scalars()
        .all()
    )
    return [_summary(db, po) for po in orders], total


def get(db: Session, *, org_id: uuid.UUID, po_id: uuid.UUID) -> PurchaseOrder:
    return _get_po(db, org_id, po_id)


def from_recommendations(
    db: Session,
    *,
    org_id: uuid.UUID,
    user_id: uuid.UUID,
    store_id: uuid.UUID,
    service_level: float,
    review_days: int,
) -> FromRecommendationsResult:
    """Create one draft order per supplier for the store's recommended items."""
    set_org_context(db, org_id)
    _require(db, Store, store_id, org_id, "Store")
    items, _ = replenishment_service.compute(
        db,
        org_id=org_id,
        service_level=service_level,
        review_days=review_days,
        store_id=store_id,
    )
    by_supplier: dict[uuid.UUID, list[POItemIn]] = defaultdict(list)
    skipped: list[SkippedItem] = []
    for item in items:
        if not item.needs_reorder:
            continue
        if item.supplier_id is None:
            skipped.append(SkippedItem(
                product_id=item.product_id, sku=item.sku, reason="Product has no supplier."
            ))
            continue
        by_supplier[item.supplier_id].append(POItemIn(
            product_id=item.product_id,
            quantity_ordered=Decimal(str(item.recommended_qty)),
        ))
    created: list[PurchaseOrder] = []
    for supplier_id, lines in by_supplier.items():
        created.append(create(
            db,
            org_id=org_id,
            user_id=user_id,
            supplier_id=supplier_id,
            store_id=store_id,
            reference=None,
            expected_date=None,
            items=lines,
            commit=False,
        ))
    db.commit()
    return FromRecommendationsResult(
        created=[_summary(db, po) for po in created],
        skipped=skipped,
    )
