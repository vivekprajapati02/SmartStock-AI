"""API tests for sales-history CSV import."""

from __future__ import annotations

from datetime import date, timedelta

from sqlalchemy import func, select

from app.models.inventory import SalesHistory
from app.services import import_service
from tests.helpers import USERS_URL, auth_header, login, register_org, tokens_from

IMPORTS_URL = "/api/v1/imports"
TODAY = date.today()
D1 = (TODAY - timedelta(days=3)).isoformat()
D2 = (TODAY - timedelta(days=2)).isoformat()
D3 = (TODAY - timedelta(days=1)).isoformat()


def _setup(client, *, org="Acme Corp", email="owner@acme-corp.com"):
    token = tokens_from(register_org(client, organization_name=org, email=email))[
        "access_token"
    ]
    headers = auth_header(token)
    client.post("/api/v1/stores", headers=headers, json={"name": "Main Store"})
    client.post(
        "/api/v1/products",
        headers=headers,
        json={"sku": "SKU-1", "name": "Widget", "unit_cost": "1", "unit_price": "2"},
    )
    return headers


def _upload(client, headers, text: str | bytes, filename: str = "sales.csv"):
    content = text.encode("utf-8") if isinstance(text, str) else text
    return client.post(
        IMPORTS_URL,
        headers=headers,
        files={"file": (filename, content, "text/csv")},
    )


def _sales_count(db) -> int:
    return int(db.execute(select(func.count()).select_from(SalesHistory)).scalar_one())


def test_valid_import_persists_rows_and_feeds_dashboard(client, db):
    headers = _setup(client)
    resp = _upload(
        client,
        headers,
        f"sku,store,sale_date,quantity\nSKU-1,Main Store,{D1},4\nSKU-1,Main Store,{D3},2.5\n",
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["status"] == "completed"
    assert (body["total_rows"], body["valid_rows"]) == (2, 2)
    assert (body["invalid_rows"], body["duplicate_rows"], body["error_count"]) == (0, 0, 0)
    assert body["errors"] == []
    assert _sales_count(db) == 2

    trend = client.get(
        "/api/v1/analytics/dashboard?trend_days=7", headers=headers
    ).json()["demand_trend"]
    by_day = {p["sale_date"]: float(p["quantity"]) for p in trend}
    assert by_day[D1] == 4
    assert by_day[D3] == 2.5
    assert by_day[D2] == 0


def test_invalid_rows_are_reported_with_exact_counts(client, db):
    headers = _setup(client)
    future = (TODAY + timedelta(days=1)).isoformat()
    csv_text = (
        "sku,store,sale_date,quantity\n"
        f"SKU-1,Main Store,{D1},3\n"  # 1 ok
        "SKU-1,Main Store,19/10/2026,3\n"  # 2 bad date format
        f"SKU-1,Main Store,{D2},-1\n"  # 3 negative
        f"NOPE,Main Store,{D2},1\n"  # 4 unknown sku
        f"SKU-1,Elsewhere,{D2},1\n"  # 5 unknown store
        f"SKU-1,Main Store,{future},1\n"  # 6 future
        f"SKU-1,Main Store,{D3},abc\n"  # 7 not a number
        f"SKU-1,Main Store,{D3},1,extra\n"  # 8 too many values
        f",Main Store,{D3},1\n"  # 9 blank sku
    )
    body = _upload(client, headers, csv_text).json()
    assert body["status"] == "partial"
    assert body["total_rows"] == 9
    assert body["valid_rows"] == 1
    assert body["invalid_rows"] == 8
    assert body["duplicate_rows"] == 0
    errors = {e["row"]: e for e in body["errors"]}
    assert sorted(errors) == [2, 3, 4, 5, 6, 7, 8, 9]
    assert errors[2]["column"] == "sale_date"
    assert "YYYY-MM-DD" in errors[2]["message"]
    assert errors[3]["column"] == "quantity"
    assert errors[4] | {"message": ""} == {
        "row": 4, "column": "sku", "value": "NOPE", "message": "", "kind": "invalid"
    }
    assert errors[5]["column"] == "store"
    assert "future" in errors[6]["message"]
    assert errors[7]["column"] == "quantity"
    assert errors[8]["column"] is None
    assert errors[9]["column"] == "sku"
    assert _sales_count(db) == 1


def test_duplicates_within_file_and_against_history(client, db):
    headers = _setup(client)
    first = _upload(
        client, headers, f"sku,store,sale_date,quantity\nSKU-1,Main Store,{D1},5\n"
    ).json()
    assert first["status"] == "completed"

    body = _upload(
        client,
        headers,
        "sku,store,sale_date,quantity\n"
        f"SKU-1,Main Store,{D1},9\n"  # already stored
        f"SKU-1,Main Store,{D2},1\n"  # new
        f"SKU-1,main store,{D2},2\n",  # same key as row 2 (store is case-insensitive)
    ).json()
    assert body["status"] == "partial"
    assert (body["valid_rows"], body["duplicate_rows"], body["invalid_rows"]) == (1, 2, 0)
    kinds = {e["row"]: (e["kind"], e["message"]) for e in body["errors"]}
    assert kinds[1][0] == "duplicate" and "already exist" in kinds[1][1]
    assert kinds[3] == ("duplicate", "Same SKU, store and date as row 2 in this file.")
    # The stored value was not overwritten.
    stored = db.execute(
        select(SalesHistory.quantity).where(SalesHistory.sale_date == date.fromisoformat(D1))
    ).scalar_one()
    assert float(stored) == 5
    assert _sales_count(db) == 2


def test_reimporting_the_same_file_saves_nothing(client, db):
    headers = _setup(client)
    text = f"sku,store,sale_date,quantity\nSKU-1,Main Store,{D1},5\n"
    _upload(client, headers, text)
    again = _upload(client, headers, text).json()
    assert again["status"] == "failed"
    assert (again["valid_rows"], again["duplicate_rows"]) == (0, 1)
    assert _sales_count(db) == 1


def test_header_is_flexible_but_required_columns_enforced(client, db):
    headers = _setup(client)
    # BOM, upper-case headers, reordered and extra columns, blank lines.
    text = f"﻿Quantity, SALE_DATE ,Store,SKU,comment\n\n2,{D2},Main Store,SKU-1,promo\n\n"
    body = _upload(client, headers, text).json()
    assert body["status"] == "completed", body
    assert body["total_rows"] == 1

    missing = _upload(client, headers, "sku,store,quantity\nSKU-1,Main Store,1\n").json()
    assert missing["status"] == "failed"
    assert missing["total_rows"] == 0
    assert missing["errors"][0]["kind"] == "file"
    assert "sale_date" in missing["errors"][0]["message"]
    assert missing["error_count"] == 1
    assert _sales_count(db) == 1


def test_file_level_failures_are_recorded(client):
    headers = _setup(client)
    cases = {
        "empty": b"",
        "header only": b"sku,store,sale_date,quantity\n",
        "not utf-8": "sku,store,sale_date,quantity\nSKU-1,Café,2026-01-01,1\n".encode("cp1252"),
        "duplicate column": b"sku,store,sale_date,quantity,sku\n",
    }
    for label, content in cases.items():
        body = _upload(client, headers, content).json()
        assert body["status"] == "failed", label
        assert body["valid_rows"] == 0, label
        assert body["errors"][0]["kind"] == "file", label

    listed = client.get(IMPORTS_URL, headers=headers).json()
    assert listed["total"] == len(cases)


def test_oversized_file_is_rejected(client, monkeypatch):
    headers = _setup(client)
    monkeypatch.setattr(import_service, "MAX_FILE_BYTES", 40)
    body = _upload(
        client, headers, "sku,store,sale_date,quantity\n" + f"SKU-1,Main Store,{D1},1\n" * 5
    ).json()
    assert body["status"] == "failed"
    assert "larger than" in body["errors"][0]["message"]


def test_error_report_is_capped_but_counts_are_exact(client, monkeypatch):
    headers = _setup(client)
    monkeypatch.setattr(import_service, "MAX_STORED_ERRORS", 3)
    text = "sku,store,sale_date,quantity\n" + "BAD,Main Store,2026-01-01,1\n" * 10
    body = _upload(client, headers, text).json()
    assert body["invalid_rows"] == 10
    assert body["error_count"] == 10
    assert len(body["errors"]) == 3
    assert body["errors_truncated"] is True


def test_conflict_at_commit_rolls_back_every_row(client, db, monkeypatch):
    headers = _setup(client)
    _upload(client, headers, f"sku,store,sale_date,quantity\nSKU-1,Main Store,{D1},5\n")
    # Simulate a concurrent writer: validation does not see the existing row,
    # so the insert hits the unique constraint at commit time.
    monkeypatch.setattr(import_service, "_existing_keys", lambda db, **kw: set())
    body = _upload(
        client,
        headers,
        f"sku,store,sale_date,quantity\nSKU-1,Main Store,{D2},1\nSKU-1,Main Store,{D1},7\n",
    ).json()
    assert body["status"] == "failed"
    assert body["valid_rows"] == 0
    assert "No rows were saved" in body["errors"][0]["message"]
    assert _sales_count(db) == 1  # neither D2 nor the conflicting row landed


def test_list_and_detail(client):
    headers = _setup(client)
    first = _upload(client, headers, f"sku,store,sale_date,quantity\nSKU-1,Main Store,{D1},1\n")
    second = _upload(
        client, headers, "sku,store,sale_date,quantity\nBAD,Main Store,2026-01-01,1\n", "b.csv"
    )
    listed = client.get(IMPORTS_URL, headers=headers).json()
    assert listed["total"] == 2
    assert [b["id"] for b in listed["items"]] == [second.json()["id"], first.json()["id"]]
    assert "errors" not in listed["items"][0]

    detail = client.get(f"{IMPORTS_URL}/{second.json()['id']}", headers=headers).json()
    assert detail["filename"] == "b.csv"
    assert detail["errors"][0]["value"] == "BAD"


def test_template_uses_real_catalogue_and_zero_quantity(client):
    headers = _setup(client)
    resp = client.get(f"{IMPORTS_URL}/template", headers=headers)
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("text/csv")
    lines = resp.text.strip().splitlines()
    assert lines[0] == "sku,store,sale_date,quantity"
    assert lines[1] == f"SKU-1,Main Store,{TODAY.isoformat()},0"

    empty_org = auth_header(
        tokens_from(register_org(client, organization_name="Empty Co", email="o@empty.com"))[
            "access_token"
        ]
    )
    assert client.get(f"{IMPORTS_URL}/template", headers=empty_org).text.strip() == (
        "sku,store,sale_date,quantity"
    )


def test_viewer_cannot_upload_but_can_read(client):
    headers = _setup(client)
    client.post(
        USERS_URL,
        headers=headers,
        json={"email": "viewer@acme-corp.com", "password": "password-123", "role": "viewer"},
    )
    viewer = auth_header(
        tokens_from(login(client, email="viewer@acme-corp.com"))["access_token"]
    )
    denied = _upload(client, viewer, f"sku,store,sale_date,quantity\nSKU-1,Main Store,{D1},1\n")
    assert denied.status_code == 403
    assert client.get(IMPORTS_URL, headers=viewer).status_code == 200


def test_imports_are_org_scoped(client):
    headers_a = _setup(client)
    batch = _upload(
        client, headers_a, f"sku,store,sale_date,quantity\nSKU-1,Main Store,{D1},1\n"
    ).json()
    headers_b = _setup(client, org="Beta Corp", email="owner@beta-corp.com")
    assert client.get(f"{IMPORTS_URL}/{batch['id']}", headers=headers_b).status_code == 404
    assert client.get(IMPORTS_URL, headers=headers_b).json()["total"] == 0
    # Org B's identical SKU/store names resolve to B's own catalogue.
    other = _upload(
        client, headers_b, f"sku,store,sale_date,quantity\nSKU-1,Main Store,{D1},1\n"
    ).json()
    assert other["status"] == "completed"


def test_missing_file_is_a_validation_error(client):
    headers = _setup(client)
    resp = client.post(IMPORTS_URL, headers=headers)
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "validation_error"
