"""PostgreSQL Row-Level Security helpers.

RLS is defence-in-depth on top of the service-layer ``org_id`` filter. Every
table that carries an ``org_id`` gets a policy that only exposes rows whose
``org_id`` matches the transaction-local ``app.current_org`` setting. When the
setting is absent the comparison is ``NULL`` and the table returns *no* rows, so
a bug that forgets to set the context fails closed rather than leaking data.

``organizations`` is intentionally excluded: it is the tenant root, has no
``org_id`` column, and must be readable during login to resolve an org by slug.
"""

from __future__ import annotations

ORG_CONTEXT_SETTING = "app.current_org"

# Tables protected by the tenant-isolation RLS policy.
ORG_SCOPED_TABLES: tuple[str, ...] = (
    "users",
    "categories",
    "suppliers",
    "stores",
    "products",
    "inventory",
    "stock_movements",
    "sales_history",
    "model_runs",
    "forecasts",
    "alerts",
    "purchase_orders",
    "purchase_order_items",
    "import_batches",
)


def _policy_name(table: str) -> str:
    return f"{table}_tenant_isolation"


def enable_rls_statements() -> list[str]:
    statements: list[str] = []
    current_org = (
        f"NULLIF(current_setting('{ORG_CONTEXT_SETTING}', true), '')::uuid"
    )
    for table in ORG_SCOPED_TABLES:
        policy = _policy_name(table)
        statements.extend(
            [
                f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY",
                f"ALTER TABLE {table} FORCE ROW LEVEL SECURITY",
                (
                    f"CREATE POLICY {policy} ON {table} "
                    f"USING (org_id = {current_org}) "
                    f"WITH CHECK (org_id = {current_org})"
                ),
            ]
        )
    return statements


def disable_rls_statements() -> list[str]:
    statements: list[str] = []
    for table in ORG_SCOPED_TABLES:
        policy = _policy_name(table)
        statements.extend(
            [
                f"DROP POLICY IF EXISTS {policy} ON {table}",
                f"ALTER TABLE {table} NO FORCE ROW LEVEL SECURITY",
                f"ALTER TABLE {table} DISABLE ROW LEVEL SECURITY",
            ]
        )
    return statements
