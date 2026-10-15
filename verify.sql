-- Run in the Supabase SQL Editor AFTER schema.sql (or the migrations/) to confirm the database
-- matches the FastAPI backend. Plain SQL, read-only, one single query: the editor shows every check
-- in one result grid. Every row must have ok = true; detail says what is missing or wrong.
WITH app_tables(name) AS (
  VALUES ('usuarios'), ('categorias'), ('muebles_catalogo'), ('habitaciones'), ('muebles_sugeridos')
),
cols AS (
  SELECT table_name::text AS t, column_name::text AS c, data_type::text AS type
  FROM information_schema.columns
  WHERE table_schema = 'public'
)
SELECT n, check_name, ok, detail
FROM (
  -- 1. The five tables of the backend exist.
  SELECT 1 AS n, 'the five tables exist' AS check_name, missing IS NULL AS ok,
         coalesce('missing: ' || missing, 'all present') AS detail
  FROM (
    SELECT string_agg(name, ', ') AS missing FROM app_tables WHERE to_regclass('public.' || name) IS NULL
  ) s
  UNION ALL
  -- 2. usuarios is the backend's table, not the incompatible one from scripts/04_security.sql.
  SELECT 2, 'usuarios has the backend columns', missing IS NULL AND NOT legacy,
         CASE WHEN legacy THEN 'usuarios comes from scripts/04_security.sql (has nombre_usuario): incompatible'
              ELSE coalesce('missing: ' || missing, 'nombre, email, password_hash') END
  FROM (
    SELECT
      (SELECT string_agg(want.col, ', ')
       FROM unnest(ARRAY['nombre', 'email', 'password_hash']) AS want(col)
       WHERE NOT EXISTS (SELECT 1 FROM cols WHERE cols.t = 'usuarios' AND cols.c = want.col)) AS missing,
      EXISTS (SELECT 1 FROM cols WHERE cols.t = 'usuarios' AND cols.c = 'nombre_usuario') AS legacy
  ) s
  UNION ALL
  -- 3. Rooms and catalog items record their owning account.
  SELECT 3, 'user_id columns exist', count(*) = 2,
         coalesce('found: ' || string_agg(t || '.user_id', ', ' ORDER BY t), 'missing on both tables')
  FROM cols
  WHERE c = 'user_id' AND t IN ('habitaciones', 'muebles_catalogo') AND type = 'character varying'
) AS checks
ORDER BY n;
