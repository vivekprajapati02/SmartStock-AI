"""v1 API router aggregation."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.v1 import analytics, auth, imports, inventory, products, users
from app.api.v1.catalog import categories_router, stores_router, suppliers_router
from app.api.v1.forecasting import forecasts_router, models_router

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(categories_router)
api_router.include_router(suppliers_router)
api_router.include_router(stores_router)
api_router.include_router(products.router)
api_router.include_router(inventory.movements_router)
api_router.include_router(inventory.router)
api_router.include_router(imports.router)
api_router.include_router(forecasts_router)
api_router.include_router(models_router)
api_router.include_router(analytics.router)
