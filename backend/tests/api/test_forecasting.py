"""API tests for backtesting, model comparison and forecast generation."""

from __future__ import annotations

import uuid
from datetime import date, timedelta

import pytest
from sqlalchemy import select

from app.ml import metrics as m
from app.models.forecasting import Forecast
from app.models.inventory import SalesHistory
from tests.helpers import USERS_URL, auth_header, login, register_org, tokens_from

WEEK = [4, 5, 6, 5, 9, 12, 7]


def _org(client, name="Acme Corp", email="owner@acme-corp.com"):
    reg = register_org(client, organization_name=name, email=email)
    headers = auth_header(tokens_from(reg)["access_token"])
    org_id = uuid.UUID(reg.json()["user"]["org_id"])
    return headers, org_id


def _catalogue(client, headers, n_products=2):
    store = client.post("/api/v1/stores", headers=headers, json={"name": "Main"}).json()
    products = [
        client.post(
            "/api/v1/products",
            headers=headers,
            json={"sku": f"SKU-{i}", "name": f"Item {i}", "unit_cost": "1", "unit_price": "2"},
        ).json()
        for i in range(n_products)
    ]
    return store, products


def _add_sales(db, org_id, store, products, days=150, end=None):
    end = end or date.today() - timedelta(days=1)
    for p_index, product in enumerate(products):
        for i in range(days):
            day = end - timedelta(days=days - 1 - i)
            qty = WEEK[day.weekday()] * (p_index + 1) + (i % 3)
            db.add(SalesHistory(
                org_id=org_id,
                product_id=uuid.UUID(product["id"]),
                store_id=uuid.UUID(store["id"]),
                sale_date=day,
                quantity=qty,
            ))
    db.flush()
    return end


@pytest.fixture()
def seeded(client, db):
    headers, org_id = _org(client)
    store, products = _catalogue(client, headers)
    end = _add_sales(db, org_id, store, products)
    return headers, org_id, store, products, end


def test_backtest_persists_one_run_per_model_with_measured_metrics(client, db, seeded):
    headers, _, _, _, end = seeded
    resp = client.post("/api/v1/models:backtest", headers=headers, json={"horizon": 7, "folds": 1})
    assert resp.status_code == 200, resp.text
    body = resp.json()
    names = {r["model_name"] for r in body["models"]}
    assert names == {"seasonal_naive", "moving_average", "exponential_smoothing", "lightgbm"}
    assert body["n_series"] == 2
    assert body["dataset_end"] == end.isoformat()
    assert body["cutoffs"] == [(end - timedelta(days=7)).isoformat()]
    assert sum(r["selected"] for r in body["models"]) == 1
    assert body["selected_model"] in names
    assert len({r["group_id"] for r in body["models"]}) == 1

    # With one fold, the stored predictions are exactly what was scored:
    # recomputing from the database reproduces the persisted metrics.
    for run in body["models"]:
        rows = db.execute(
            select(Forecast.y_true, Forecast.y_pred).where(
                Forecast.model_run_id == uuid.UUID(run["id"])
            )
        ).all()
        assert len(rows) == 2 * 7
        actual = [float(a) for a, _ in rows]
        pred = [float(p) for _, p in rows]
        assert run["metrics"]["n_points"] == 14
        assert run["metrics"]["mae"] == pytest.approx(m.mae(actual, pred), abs=1e-3)
        assert run["metrics"]["wape"] == pytest.approx(m.wape(actual, pred), abs=1e-3)

    # forecast_vs_actual sums the selected model's fold per day.
    fva = body["forecast_vs_actual"]
    assert [p["day"] for p in fva] == [
        (end - timedelta(days=6 - i)).isoformat() for i in range(7)
    ]
    total_actual = db.execute(
        select(SalesHistory.quantity).where(
            SalesHistory.sale_date > end - timedelta(days=7)
        )
    ).scalars().all()
    assert sum(p["actual"] for p in fva) == pytest.approx(float(sum(total_actual)))


def test_comparison_reports_selection_against_best_baseline(client, seeded):
    headers = seeded[0]
    client.post("/api/v1/models:backtest", headers=headers, json={"horizon": 14})
    body = client.get("/api/v1/models/comparison?horizon=14", headers=headers).json()
    assert body["folds"] == 3
    wapes = {r["model_name"]: r["metrics"]["wape"] for r in body["models"]}
    baselines = {k: v for k, v in wapes.items() if k != "lightgbm"}
    best = min(baselines, key=baselines.get)
    assert body["best_baseline"] == best
    if wapes["lightgbm"] < baselines[best]:
        assert body["selected_model"] == "lightgbm"
        assert body["wape_improvement_vs_baseline"] > 0
    else:
        assert body["selected_model"] == best
        assert body["wape_improvement_vs_baseline"] == 0
    # Sorted best-first by WAPE.
    assert [r["metrics"]["wape"] for r in body["models"]] == sorted(wapes.values())


def test_generate_forecasts_with_selected_model(client, seeded):
    headers, _, store, products, end = seeded
    resp = client.post("/api/v1/forecasts:generate", headers=headers, json={"horizon": 14})
    assert resp.status_code == 200, resp.text
    body = resp.json()
    run = body["run"]
    assert run["kind"] == "forecast"
    comparison = client.get("/api/v1/models/comparison?horizon=14", headers=headers).json()
    assert run["model_name"] == comparison["selected_model"]
    assert run["params"]["backtest_metrics"]["n_points"] > 0
    assert body["total"] == 2 * 14
    dates = sorted({p["forecast_date"] for p in body["items"]})
    assert dates[0] == (end + timedelta(days=1)).isoformat()
    assert all(p["quantity"] >= 0 for p in body["items"])

    series = client.get(
        "/api/v1/forecasts/series",
        headers=headers,
        params={"product_id": products[0]["id"], "store_id": store["id"], "horizon": 14},
    ).json()
    assert len(series["history"]) == 60
    assert series["history"][-1]["day"] == end.isoformat()
    assert len(series["forecast"]) == 14
    assert series["run"]["id"] == run["id"]

    filtered = client.get(
        "/api/v1/forecasts",
        headers=headers,
        params={"horizon": 14, "product_id": products[1]["id"], "limit": 500},
    ).json()
    assert filtered["total"] == 14
    assert {p["sku"] for p in filtered["items"]} == {"SKU-1"}


def test_regenerating_replaces_the_previous_forecast_run(client, db, seeded):
    headers = seeded[0]
    first = client.post("/api/v1/forecasts:generate", headers=headers, json={"horizon": 7})
    second = client.post("/api/v1/forecasts:generate", headers=headers, json={"horizon": 7})
    assert first.json()["run"]["id"] != second.json()["run"]["id"]
    runs = client.get(
        "/api/v1/models/runs?horizon=7&kind=forecast", headers=headers
    ).json()
    assert runs["total"] == 1
    # Generation reused the existing backtest instead of running another.
    backtests = client.get(
        "/api/v1/models/runs?horizon=7&kind=backtest", headers=headers
    ).json()
    assert backtests["total"] == 4


def test_empty_org_returns_empty_results_not_numbers(client):
    headers, _ = _org(client)
    comparison = client.get("/api/v1/models/comparison?horizon=30", headers=headers).json()
    assert comparison["models"] == [] and comparison["selected_model"] is None
    forecasts = client.get("/api/v1/forecasts", headers=headers).json()
    assert forecasts == {"run": None, "items": [], "total": 0, "limit": 50, "offset": 0}
    for url, payload in (
        ("/api/v1/models:backtest", {"horizon": 7}),
        ("/api/v1/forecasts:generate", {"horizon": 7}),
    ):
        resp = client.post(url, headers=headers, json=payload)
        assert resp.status_code == 422
        assert "sales history" in resp.json()["error"]["message"]


def test_insufficient_history_for_long_horizon(client, db):
    headers, org_id = _org(client)
    store, products = _catalogue(client, headers, n_products=1)
    _add_sales(db, org_id, store, products, days=100)
    resp = client.post("/api/v1/models:backtest", headers=headers, json={"horizon": 90})
    assert resp.status_code == 422
    assert "days of sales history" in resp.json()["error"]["message"]


def test_horizon_must_be_supported(client, seeded):
    headers = seeded[0]
    resp = client.post("/api/v1/models:backtest", headers=headers, json={"horizon": 10})
    assert resp.status_code == 422
    assert client.get("/api/v1/models/comparison?horizon=10", headers=headers).status_code == 422


def test_viewer_can_read_but_not_run(client, seeded):
    headers = seeded[0]
    client.post(
        USERS_URL,
        headers=headers,
        json={"email": "viewer@acme-corp.com", "password": "password-123", "role": "viewer"},
    )
    viewer = auth_header(tokens_from(login(client, email="viewer@acme-corp.com"))["access_token"])
    assert client.post(
        "/api/v1/models:backtest", headers=viewer, json={"horizon": 7}
    ).status_code == 403
    assert client.post(
        "/api/v1/forecasts:generate", headers=viewer, json={"horizon": 7}
    ).status_code == 403
    assert client.get("/api/v1/models/comparison", headers=viewer).status_code == 200
    assert client.get("/api/v1/forecasts", headers=viewer).status_code == 200


def test_forecasting_is_org_scoped(client, seeded):
    headers_a, _, store, products, _ = seeded
    client.post("/api/v1/forecasts:generate", headers=headers_a, json={"horizon": 7})
    headers_b, _ = _org(client, name="Beta Corp", email="owner@beta-corp.com")
    assert client.get("/api/v1/forecasts", headers=headers_b).json()["total"] == 0
    assert client.get(
        "/api/v1/models/comparison?horizon=7", headers=headers_b
    ).json()["models"] == []
    resp = client.get(
        "/api/v1/forecasts/series",
        headers=headers_b,
        params={"product_id": products[0]["id"], "store_id": store["id"]},
    )
    assert resp.status_code == 404
