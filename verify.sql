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
) AS checks
ORDER BY n;
