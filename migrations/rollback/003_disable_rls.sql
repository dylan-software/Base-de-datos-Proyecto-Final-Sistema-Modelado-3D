-- Rollback of migration 003: turn Row Level Security off on the five app tables.
--
-- WARNING: this reopens the Supabase REST API on these tables. Depending on the grants of the anon and
-- authenticated roles, anyone with the project's public anon key could then read emails and password
-- hashes from usuarios. Only use it to diagnose a problem, and run 003_enable_rls.sql again afterwards.
--
-- Tables other than these five that migration 003 may have switched on are left untouched: there is
-- no record of which ones it changed. The backend is not affected either way (it owns the tables).
--
-- Plain SQL. Running it again is a no-op.

BEGIN;

ALTER TABLE usuarios DISABLE ROW LEVEL SECURITY;
ALTER TABLE categorias DISABLE ROW LEVEL SECURITY;
ALTER TABLE muebles_catalogo DISABLE ROW LEVEL SECURITY;
ALTER TABLE habitaciones DISABLE ROW LEVEL SECURITY;
ALTER TABLE muebles_sugeridos DISABLE ROW LEVEL SECURITY;

COMMIT;
