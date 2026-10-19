-- Runs once when the PostgreSQL container initialises an empty data volume.
--
-- The API must NOT connect as a superuser: superusers (and BYPASSRLS roles)
-- skip row-level security even with FORCE ROW LEVEL SECURITY, which would
-- disable the database-level tenant isolation. The application role owns its
-- database so migrations can create tables, and FORCE makes the RLS policies
-- apply to it as the table owner.
CREATE ROLE smartstock LOGIN PASSWORD 'smartstock' NOSUPERUSER NOBYPASSRLS NOCREATEROLE;
CREATE DATABASE smartstock OWNER smartstock;
