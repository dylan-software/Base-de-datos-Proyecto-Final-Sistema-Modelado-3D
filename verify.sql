-- Run in the Supabase SQL Editor AFTER schema.sql (or the migrations/) to confirm the database
-- matches the FastAPI backend. Plain SQL, read-only, one single query: the editor shows every check
-- in one result grid. Every row must have ok = true; detail says what is missing or wrong.
WITH app_tables(name) AS (
  VALUES ('usuarios'), ('categorias'), ('muebles_catalogo'), ('grupos_proyecto'), ('habitaciones'),
         ('muebles_sugeridos'), ('publicaciones_proyecto')
),
cols AS (
  SELECT table_name::text AS t, column_name::text AS c, data_type::text AS type,
         character_maximum_length::int AS maxlen, is_nullable::text AS nullable,
         column_default::text AS def
  FROM information_schema.columns
  WHERE table_schema = 'public'
)
SELECT n, check_name, ok, detail
FROM (
  -- 1. The seven tables of the backend exist.
  SELECT 1 AS n, 'the seven tables exist' AS check_name, missing IS NULL AS ok,
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
  -- 5. The ten indexes of the models exist; the two unique ones are unique (the two UNIQUE constraints
  --    of publicaciones_proyecto are checked in 18).
  SELECT 5, 'the ten indexes exist', missing IS NULL AND not_unique IS NULL,
         coalesce(nullif(concat_ws(' ', 'missing: ' || missing, 'not unique: ' || not_unique), ''), 'all present')
  FROM (
    SELECT
      (SELECT string_agg(idx.name, ', ')
       FROM unnest(ARRAY[
         'ix_usuarios_email', 'uq_categorias_nombre_lower', 'ix_muebles_catalogo_categoria_id',
         'ix_muebles_catalogo_user_id', 'ix_grupos_proyecto_user_id', 'ix_habitaciones_user_id',
         'ix_habitaciones_grupo_id', 'ix_muebles_sugeridos_habitacion_id',
         'ix_publicaciones_proyecto_user_id', 'ix_publicaciones_proyecto_catalogo'
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
  SELECT 7, 'RLS is on for the seven tables', missing IS NULL, coalesce('without RLS: ' || missing, 'all seven')
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
  UNION ALL
  -- 9. RLS without policies: anon and authenticated get nothing. A policy here would reopen the API.
  SELECT 9, 'no RLS policies on the app tables', count(*) = 0,
         coalesce('policies: ' || string_agg(tablename::text || '.' || policyname::text, ', '), 'none')
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename::text IN (SELECT name FROM app_tables)
  UNION ALL
  -- 10. The backend connects as the owner, which bypasses RLS, unless RLS is FORCEd on the table.
  SELECT 10, 'the app tables are owned by the current role, RLS not forced',
         count(*) = 7 AND coalesce(bool_and(owned), false) AND NOT coalesce(bool_or(forced), false),
         coalesce(string_agg(name || ': ' || owner || CASE WHEN forced THEN ' (FORCE RLS)' ELSE '' END,
                             ', ' ORDER BY name), 'no tables')
           || ' (current role: ' || current_user || ')'
  FROM (
    SELECT a.name, pg_get_userbyid(c.relowner)::text AS owner, pg_has_role(c.relowner, 'USAGE') AS owned,
           c.relforcerowsecurity AS forced
    FROM app_tables a
    JOIN pg_class c ON c.oid = to_regclass('public.' || a.name)
  ) s
  UNION ALL
  -- 11. Every column except id is documented (units: catalog in cm, rooms and placed furniture in m).
  SELECT 11, 'every column except id has a comment', missing IS NULL,
         coalesce('without comment: ' || missing, 'all documented')
  FROM (
    SELECT string_agg(cols.t || '.' || cols.c, ', ' ORDER BY cols.t, cols.c) AS missing
    FROM cols
    JOIN pg_attribute att ON att.attrelid = to_regclass('public.' || cols.t) AND att.attname = cols.c
    WHERE cols.t IN (SELECT name FROM app_tables) AND cols.c <> 'id'
      AND col_description(att.attrelid, att.attnum) IS NULL
  ) s
  UNION ALL
  -- 12. grupos_proyecto (migration 005) has its columns with the right type, length, NULL rule and
  --     the now() default on creado_en.
  SELECT 12, 'grupos_proyecto columns and types', missing IS NULL,
         coalesce('missing or wrong: ' || missing, 'user_id, nombre, descripcion, creado_en')
  FROM (
    SELECT string_agg(want.c, ', ') AS missing
    FROM (VALUES
      ('user_id', 'character varying', 64, 'NO'),
      ('nombre', 'character varying', 80, 'NO'),
      ('descripcion', 'text', NULL, 'YES'),
      ('creado_en', 'timestamp with time zone', NULL, 'NO')
    ) AS want(c, type, maxlen, nullable)
    WHERE NOT EXISTS (
      SELECT 1 FROM cols
      WHERE cols.t = 'grupos_proyecto' AND cols.c = want.c AND cols.type = want.type
        AND cols.maxlen IS NOT DISTINCT FROM want.maxlen AND cols.nullable = want.nullable
        AND (want.c <> 'creado_en' OR cols.def ILIKE '%now()%')
    )
  ) s
  UNION ALL
  -- 13. habitaciones has the group, description and (reserved) derived-from columns, all nullable.
  SELECT 13, 'habitaciones group columns and types', missing IS NULL,
         coalesce('missing or wrong: ' || missing, 'grupo_id, descripcion, derivado_de')
  FROM (
    SELECT string_agg(want.c, ', ') AS missing
    FROM (VALUES ('grupo_id', 'integer'), ('descripcion', 'text'), ('derivado_de', 'integer')) AS want(c, type)
    WHERE NOT EXISTS (
      SELECT 1 FROM cols
      WHERE cols.t = 'habitaciones' AND cols.c = want.c AND cols.type = want.type AND cols.nullable = 'YES'
    )
  ) s
  UNION ALL
  -- 14. Deleting a group or a source project never deletes a project: both links become NULL.
  SELECT 14, 'grupo_id and derivado_de are ON DELETE SET NULL', missing IS NULL,
         coalesce('missing: ' || missing, 'grupo_id -> grupos_proyecto(id), derivado_de -> habitaciones(id)')
  FROM (
    SELECT string_agg(want.col, ', ') AS missing
    FROM (VALUES ('grupo_id', 'grupos_proyecto'), ('derivado_de', 'habitaciones')) AS want(col, ref)
    WHERE NOT EXISTS (
      SELECT 1
      FROM pg_constraint k
      JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = k.conkey[1]
      WHERE k.conrelid = to_regclass('public.habitaciones') AND k.contype = 'f'
        AND cardinality(k.conkey) = 1 AND a.attname = want.col
        AND k.confrelid = to_regclass('public.' || want.ref) AND k.confdeltype = 'n'
    )
  ) s
  UNION ALL
  -- 15. Both descriptions are limited to 1000 characters by a named CHECK.
  SELECT 15, 'descriptions are limited to 1000 characters', missing IS NULL,
         coalesce('missing: ' || missing, 'ck_grupos_proyecto_descripcion_len, ck_habitaciones_descripcion_len')
  FROM (
    SELECT string_agg(want.name, ', ') AS missing
    FROM (VALUES
      ('grupos_proyecto', 'ck_grupos_proyecto_descripcion_len'),
      ('habitaciones', 'ck_habitaciones_descripcion_len')
    ) AS want(tbl, name)
    WHERE NOT EXISTS (
      SELECT 1 FROM pg_constraint k
      WHERE k.conrelid = to_regclass('public.' || want.tbl) AND k.contype = 'c' AND k.conname = want.name
        AND pg_get_constraintdef(k.oid) LIKE '%1000%'
    )
  ) s
  UNION ALL
  -- 16. Explicitly for the new table: RLS on, not forced and without policies. A table created by the
  --     backend's create_all does not have RLS until its startup migration (or 005) turns it on.
  SELECT 16, 'RLS is on for grupos_proyecto, not forced, no policies',
         coalesce(c.relrowsecurity, false) AND NOT coalesce(c.relforcerowsecurity, false) AND policies = 0,
         CASE WHEN c.oid IS NULL THEN 'table missing'
              WHEN NOT c.relrowsecurity THEN 'RLS off: the Supabase REST API can read every group'
              WHEN c.relforcerowsecurity THEN 'RLS forced: the backend (owner) would be blocked'
              WHEN policies > 0 THEN policies || ' policies: they reopen the REST API'
              ELSE 'on, not forced, no policies' END
  FROM (
    SELECT to_regclass('public.grupos_proyecto') AS oid,
           (SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'grupos_proyecto') AS policies
  ) g
  LEFT JOIN pg_class c ON c.oid = g.oid
  UNION ALL
  -- 17. publicaciones_proyecto (migration 006) has its columns with the right type, length and NULL rule;
  --     publica defaults to false (private by default), copias to 0 and both dates to now().
  SELECT 17, 'publicaciones_proyecto columns, types and defaults', missing IS NULL,
         coalesce('missing or wrong: ' || missing, 'publica false by default; 10 columns as expected')
  FROM (
    SELECT string_agg(want.c, ', ') AS missing
    FROM (VALUES
      ('codigo', 'character varying', 24, 'NO', NULL),
      ('user_id', 'character varying', 64, 'NO', NULL),
      ('habitacion_id', 'integer', NULL, 'NO', NULL),
      ('publica', 'boolean', NULL, 'NO', 'false'),
      ('titulo', 'character varying', 120, 'NO', NULL),
      ('descripcion', 'text', NULL, 'YES', NULL),
      ('documento', 'jsonb', NULL, 'NO', NULL),
      ('copias', 'integer', NULL, 'NO', '0'),
      ('creada_en', 'timestamp with time zone', NULL, 'NO', 'now()'),
      ('actualizada_en', 'timestamp with time zone', NULL, 'NO', 'now()')
    ) AS want(c, type, maxlen, nullable, def)
    WHERE NOT EXISTS (
      SELECT 1 FROM cols
      WHERE cols.t = 'publicaciones_proyecto' AND cols.c = want.c AND cols.type = want.type
        AND cols.maxlen IS NOT DISTINCT FROM want.maxlen AND cols.nullable = want.nullable
        AND (want.def IS NULL OR cols.def ILIKE '%' || want.def || '%')
    )
  ) s
  UNION ALL
  -- 18. One publication per project, deleted with it, and unique public codes.
  SELECT 18, 'publications cascade on room delete; codigo and habitacion_id unique',
         cascade_ok AND missing IS NULL,
         concat_ws('; ',
           CASE WHEN cascade_ok THEN 'habitacion_id -> habitaciones(id) ON DELETE CASCADE'
                ELSE 'habitacion_id is not ON DELETE CASCADE to habitaciones' END,
           coalesce('missing unique: ' || missing, 'uq_publicaciones_proyecto_codigo, uq_publicaciones_proyecto_habitacion_id'))
  FROM (
    SELECT
      EXISTS (
        SELECT 1
        FROM pg_constraint k
        JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = k.conkey[1]
        WHERE k.conrelid = to_regclass('public.publicaciones_proyecto') AND k.contype = 'f'
          AND cardinality(k.conkey) = 1 AND a.attname = 'habitacion_id'
          AND k.confrelid = to_regclass('public.habitaciones') AND k.confdeltype = 'c'
      ) AS cascade_ok,
      (SELECT string_agg(want.name, ', ')
       FROM (VALUES ('uq_publicaciones_proyecto_codigo'), ('uq_publicaciones_proyecto_habitacion_id')) AS want(name)
       WHERE NOT EXISTS (
         SELECT 1 FROM pg_constraint k
         WHERE k.conrelid = to_regclass('public.publicaciones_proyecto') AND k.contype = 'u' AND k.conname = want.name
       )) AS missing
  ) s
  UNION ALL
  -- 19. The three named CHECKs: public description <= 1000 characters, frozen copy <= 262144 characters
  --     and a copy counter that is never negative.
  SELECT 19, 'publication CHECKs (description, document size, copies)', missing IS NULL,
         coalesce('missing: ' || missing,
                  'ck_publicaciones_proyecto_descripcion_len, ck_publicaciones_proyecto_documento_len, ck_publicaciones_proyecto_copias')
  FROM (
    SELECT string_agg(want.name, ', ') AS missing
    FROM (VALUES
      ('ck_publicaciones_proyecto_descripcion_len', '%1000%'),
      ('ck_publicaciones_proyecto_documento_len', '%262144%'),
      ('ck_publicaciones_proyecto_copias', '%>= 0%')
    ) AS want(name, def)
    WHERE NOT EXISTS (
      SELECT 1 FROM pg_constraint k
      WHERE k.conrelid = to_regclass('public.publicaciones_proyecto') AND k.contype = 'c' AND k.conname = want.name
        AND pg_get_constraintdef(k.oid) LIKE want.def
    )
  ) s
  UNION ALL
  -- 20. Explicitly for the new table: RLS on, not forced and without policies, so the Supabase REST API
  --     sees nothing (not even the public rows) and the backend (owner) is not affected.
  SELECT 20, 'RLS is on for publicaciones_proyecto, not forced, no policies',
         coalesce(c.relrowsecurity, false) AND NOT coalesce(c.relforcerowsecurity, false) AND policies = 0,
         CASE WHEN c.oid IS NULL THEN 'table missing'
              WHEN NOT c.relrowsecurity THEN 'RLS off: the Supabase REST API can read every publication and its owner'
              WHEN c.relforcerowsecurity THEN 'RLS forced: the backend (owner) would be blocked'
              WHEN policies > 0 THEN policies || ' policies: they reopen the REST API'
              ELSE 'on, not forced, no policies' END
  FROM (
    SELECT to_regclass('public.publicaciones_proyecto') AS oid,
           (SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'publicaciones_proyecto') AS policies
  ) g
  LEFT JOIN pg_class c ON c.oid = g.oid
) AS checks
ORDER BY n;
