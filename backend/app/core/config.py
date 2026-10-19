"""Application configuration loaded from environment variables and `.env`."""

from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime settings.

    Values are read from environment variables first, then from a local `.env`
    file. Secrets such as ``JWT_SECRET_KEY`` never have production defaults so a
    misconfigured deployment fails fast instead of silently using a weak key.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    app_name: str = "SmartStock AI"
    environment: Literal["development", "test", "staging", "production"] = "development"
    debug: bool = False
    log_level: str = "INFO"

    database_url: str = "postgresql+psycopg2://smartstock:smartstock@localhost:5432/smartstock"
    test_database_url: str | None = None

    jwt_secret_key: str = "insecure-development-only-secret-change-me"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 30
    refresh_token_expire_days: int = 7

    cors_origins: str = "*"

    @field_validator("log_level")
    @classmethod
    def _normalise_log_level(cls, value: str) -> str:
        return value.upper()

    @property
    def cors_origin_list(self) -> list[str]:
        if self.cors_origins.strip() == "*":
            return ["*"]
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @property
    def is_production(self) -> bool:
        return self.environment == "production"

    def sqlalchemy_engine_kwargs(self) -> dict:
        """Engine kwargs tuned per dialect (pooling differs for SQLite)."""
        if self.database_url.startswith("sqlite"):
            from sqlalchemy.pool import StaticPool

            return {
                "connect_args": {"check_same_thread": False},
                "poolclass": StaticPool,
            }
        return {"pool_pre_ping": True, "pool_size": 5, "max_overflow": 10}


@lru_cache
def get_settings() -> Settings:
    return Settings()
