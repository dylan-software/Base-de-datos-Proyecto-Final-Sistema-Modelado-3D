-- Migration 003: Row Level Security, without policies, on every app table.
--
-- Supabase exposes every table in "public" through its REST API. RLS with no policies closes that API
-- for the anon and authenticated roles. The backend connects as the owner of the tables, and owners
-- bypass RLS, so it keeps working. The backend never does this by itself: it must be run by hand.
--
-- Idempotent and plain SQL. Undo with rollback/003_disable_rls.sql.

BEGIN;

-- Most sensitive table: emails and password hashes.
ALTER TABLE usuarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE categorias ENABLE ROW LEVEL SECURITY;
ALTER TABLE muebles_catalogo ENABLE ROW LEVEL SECURITY;
ALTER TABLE habitaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE muebles_sugeridos ENABLE ROW LEVEL SECURITY;

-- Any other table in "public" that the current role owns (e.g. the old Node backend's furniture,
-- projects, spaces, placed_items). Extension tables and tables of other roles are skipped, as in
-- schema.sql; verify.sql lists whatever is left without RLS.
DO $$
DECLARE
  t regclass;
BEGIN
  FOR t IN
    SELECT c.oid::regclass
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p')
      AND NOT c.relrowsecurity
      AND pg_has_role(c.relowner, 'USAGE')
      AND NOT EXISTS (
        SELECT 1 FROM pg_depend d
        WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e'
      )
  LOOP
    EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', t);
    RAISE NOTICE 'RLS enabled on %', t;
  END LOOP;
END
$$;

COMMIT;
