"""Role definitions and the privilege hierarchy used for authorization.

Roles are ordered; a higher-ranked role implicitly satisfies any requirement of
a lower-ranked role. The ``Role`` enum lives in ``core`` (not ``models``) so the
authorization helpers have no dependency on the ORM layer.
"""

from __future__ import annotations

from enum import StrEnum


class Role(StrEnum):
    OWNER = "owner"
    ADMIN = "admin"
    MANAGER = "manager"
    VIEWER = "viewer"


ROLE_RANK: dict[Role, int] = {
    Role.VIEWER: 1,
    Role.MANAGER: 2,
    Role.ADMIN: 3,
    Role.OWNER: 4,
}


def role_at_least(role: Role | str, minimum: Role | str) -> bool:
    """Return True when ``role`` ranks at or above ``minimum``."""
    try:
        role_enum = Role(role)
        minimum_enum = Role(minimum)
    except ValueError:
        return False
    return ROLE_RANK[role_enum] >= ROLE_RANK[minimum_enum]
