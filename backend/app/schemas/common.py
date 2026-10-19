"""Shared schema primitives: base model, pagination, and error envelopes."""

from __future__ import annotations

from typing import Generic, TypeVar

from pydantic import BaseModel, ConfigDict, Field

T = TypeVar("T")


class APIModel(BaseModel):
    """Base for all request/response models."""

    model_config = ConfigDict(from_attributes=True)


class ErrorDetail(APIModel):
    field: str | None = None
    message: str
    type: str | None = None


class ErrorBody(APIModel):
    code: str
    message: str
    details: list[ErrorDetail] | None = None
    request_id: str | None = None


class ErrorResponse(APIModel):
    """The single error envelope used by every endpoint."""

    error: ErrorBody


class Page(APIModel, Generic[T]):
    items: list[T]
    total: int = Field(ge=0)
    limit: int = Field(ge=1)
    offset: int = Field(ge=0)


class Message(APIModel):
    message: str
