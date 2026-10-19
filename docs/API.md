# API Reference (v1)

Base URL: `/api/v1`. Interactive docs: `/docs`. OpenAPI: `/openapi.json`.

## Error envelope

Every error response has the same shape:

```json
{
  "error": {
    "code": "validation_error",
    "message": "The request payload failed validation.",
    "details": [{"field": "email", "message": "value is not a valid email address", "type": "value_error"}],
    "request_id": "8f1c..."
  }
}
```

Common codes: `validation_error` (422), `unauthenticated` (401),
`permission_denied` (403), `not_found` (404), `conflict` (409),
`internal_error` (500).

## Health

### `GET /health`
Liveness probe.

```json
{ "status": "ok", "app": "SmartStock AI", "environment": "development" }
```

### `GET /health/ready`
Readiness probe; verifies database connectivity.

```json
{ "status": "ready", "database": "ok" }
```

## Authentication

### `POST /api/v1/auth/register`
Creates a new organisation and its `owner` user in one transaction.

Request:
```json
{
  "organization_name": "Acme Corp",
  "organization_slug": "acme-corp",
  "email": "owner@acme-corp.com",
  "password": "password-123",
  "full_name": "Owner"
}
```

Response `201`:
```json
{
  "user": { "id": "...", "org_id": "...", "email": "owner@acme-corp.com", "role": "owner", "is_active": true, "created_at": "..." },
  "tokens": { "access_token": "...", "refresh_token": "...", "token_type": "bearer", "expires_in": 1800 }
}
```

Errors: `409` if the organisation name/slug already exists; `422` for invalid
email or weak password (min 8 characters, max 72 bytes UTF-8).

### `POST /api/v1/auth/login`
Request:
```json
{ "organization": "acme-corp", "email": "owner@acme-corp.com", "password": "password-123" }
```
Response `200` with the same shape as register. `401` on any mismatch.

### `POST /api/v1/auth/refresh`
Request:
```json
{ "refresh_token": "..." }
```
Response `200` with a new token pair. `401` if the token is expired, invalid, or
is not a refresh token.

### `GET /api/v1/auth/me`
Requires `Authorization: Bearer <access_token>`. Returns the current user.

## Users

Requires role `admin` or `owner`.

### `GET /api/v1/users?limit=50&offset=0`
Returns a page of users in the caller's organisation.

```json
{ "items": [ { "id": "...", "email": "...", "role": "viewer" } ], "total": 1, "limit": 50, "offset": 0 }
```

### `POST /api/v1/users`
Request:
```json
{ "email": "manager@acme-corp.com", "password": "password-123", "full_name": "Manager", "role": "manager" }
```
Response `201` with the created user. `409` if the email already exists in the
organisation.

## Authorization model

| Role | Rank |
|------|------|
| `viewer` | 1 |
| `manager` | 2 |
| `admin` | 3 |
| `owner` | 4 |

An endpoint requiring role R accepts any role with rank ≥ R.
