"""Unit tests for the role hierarchy."""

from __future__ import annotations

import pytest

from app.core.rbac import Role, role_at_least


@pytest.mark.parametrize(
    ("role", "minimum", "expected"),
    [
        (Role.OWNER, Role.VIEWER, True),
        (Role.OWNER, Role.OWNER, True),
        (Role.ADMIN, Role.MANAGER, True),
        (Role.MANAGER, Role.ADMIN, False),
        (Role.VIEWER, Role.MANAGER, False),
        (Role.VIEWER, Role.VIEWER, True),
        ("admin", "manager", True),
        ("nonsense", "viewer", False),
    ],
)
def test_role_at_least(role, minimum, expected):
    assert role_at_least(role, minimum) is expected
