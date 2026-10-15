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
  UNION ALL
  -- 4. The editable floor polygon column exists with the right type.
  SELECT 4, 'habitaciones.vertices is jsonb', coalesce(bool_and(type = 'jsonb'), false),
         coalesce('type: ' || max(type), 'column missing')
  FROM cols
  WHERE t = 'habitaciones' AND c = 'vertices'
  UNION ALL
  -- 5. The six indexes of the models exist; the two unique ones are unique.
  SELECT 5, 'the six indexes exist', missing IS NULL AND not_unique IS NULL,
         coalesce(nullif(concat_ws(' ', 'missing: ' || missing, 'not unique: ' || not_unique), ''), 'all present')
  FROM (
    SELECT
      (SELECT string_agg(idx.name, ', ')
       FROM unnest(ARRAY[
         'ix_usuarios_email', 'uq_categorias_nombre_lower', 'ix_muebles_catalogo_categoria_id',
         'ix_muebles_catalogo_user_id', 'ix_habitaciones_user_id', 'ix_muebles_sugeridos_habitacion_id'
       ]) AS idx(name)
       WHERE to_regclass('public.' || idx.name) IS NULL) AS missing,
      (SELECT string_agg(idx.name, ', ')
       FROM unnest(ARRAY['ix_usuarios_email', 'uq_categorias_nombre_lower']) AS idx(name)
       WHERE NOT EXISTS (
         SELECT 1 FROM pg_index x WHERE x.indexrelid = to_regclass('public.' || idx.name) AND x.indisunique
       )) AS not_unique
  ) s
  UNION ALL
  -- 6. Deleting a room deletes its placed furniture.
  SELECT 6, 'muebles_sugeridos cascades on room delete',
         EXISTS (
           SELECT 1 FROM pg_constraint
           WHERE conrelid = to_regclass('public.muebles_sugeridos') AND contype = 'f'
             AND confrelid = to_regclass('public.habitaciones') AND confdeltype = 'c'
         ),
         'habitacion_id -> habitaciones(id) ON DELETE CASCADE'
  UNION ALL
  -- 7. RLS closes the Supabase REST API on every app table, usuarios included.
  SELECT 7, 'RLS is on for the five tables', missing IS NULL, coalesce('without RLS: ' || missing, 'all five')
  FROM (
    SELECT string_agg(a.name, ', ') AS missing
    FROM app_tables a
    LEFT JOIN pg_class c ON c.oid = to_regclass('public.' || a.name)
    WHERE c.relrowsecurity IS NOT TRUE
  ) s
  UNION ALL
  -- 8. Other public tables without RLS. Only extension tables or tables owned by another role
  --    (e.g. PostGIS's spatial_ref_sys) may remain; they are listed for review.
  SELECT 8, 'no other owned public table lacks RLS', count(*) FILTER (WHERE owned AND NOT extension) = 0,
         coalesce(string_agg(name || CASE WHEN extension THEN ' (extension)'
                                          WHEN NOT owned THEN ' (owner: ' || owner || ')' ELSE '' END,
                             ', ' ORDER BY name), 'none')
  FROM (
    SELECT c.relname::text AS name, pg_get_userbyid(c.relowner)::text AS owner,
           pg_has_role(c.relowner, 'USAGE') AS owned,
           EXISTS (
             SELECT 1 FROM pg_depend d
             WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e'
           ) AS extension
    FROM pg_class c
    JOIN pg_namespace ns ON ns.oid = c.relnamespace
    WHERE ns.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relrowsecurity
  ) s
) AS checks
ORDER BY n;
