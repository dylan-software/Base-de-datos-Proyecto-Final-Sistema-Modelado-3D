-- With RLS on and no policies, Supabase's anon and authenticated roles (the ones behind the public REST
-- API) can neither read nor write any app table, even when the tables have rows. Run on an empty
-- database after schema.sql.
--
-- Supabase only: elsewhere those roles do not exist, or this session cannot switch to them, and the test
-- prints SKIP instead of PASS.
BEGIN;

-- One row per app table, inserted as the owner, so "0 rows" really means "hidden by RLS".
DO $$
DECLARE
  cat_id integer;
  room_id integer;
BEGIN
  INSERT INTO usuarios (nombre, email, password_hash) VALUES ('Ana', 'ana@example.com', 'scrypt$00$00');
  INSERT INTO categorias (nombre) VALUES ('Asientos') RETURNING id INTO cat_id;
  INSERT INTO muebles_catalogo (user_id, categoria_id, nombre, ancho, alto, profundidad)
  VALUES ('1', cat_id, 'Silla', 45, 90, 50);
  INSERT INTO habitaciones (user_id, nombre, ancho, alto, profundidad) VALUES ('1', 'Sala', 4, 2.5, 5)
  RETURNING id INTO room_id;
  INSERT INTO muebles_sugeridos (habitacion_id, nombre, ancho, alto, profundidad, posicion_x, posicion_y, posicion_z)
  VALUES (room_id, 'Silla', 0.45, 0.9, 0.5, 1, 0, 1);
END
$$;

DO $$
DECLARE
  api_role text;
  app_table text;
  visible bigint;
BEGIN
  FOREACH api_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = api_role)
       OR NOT pg_has_role(current_user, api_role, 'MEMBER') THEN
      RAISE NOTICE 'SKIP: test_rls_blocks_anon: role % does not exist or cannot be assumed (not Supabase)', api_role;
      CONTINUE;
    END IF;

    EXECUTE format('SET LOCAL ROLE %I', api_role);

    FOREACH app_table IN ARRAY ARRAY['usuarios', 'categorias', 'muebles_catalogo', 'habitaciones', 'muebles_sugeridos'] LOOP
      -- Reading: either no privilege at all or zero visible rows.
      BEGIN
        EXECUTE format('SELECT count(*) FROM %I', app_table) INTO visible;
        IF visible > 0 THEN
          RAISE EXCEPTION 'FAIL: test_rls_blocks_anon: % can read % rows of %', api_role, visible, app_table;
        END IF;
      EXCEPTION WHEN insufficient_privilege THEN
        NULL;
      END;
    END LOOP;

    -- Writing: rejected either by missing privilege or by RLS (both are SQLSTATE 42501).
    BEGIN
      INSERT INTO categorias (nombre) VALUES ('Creada desde la API');
      RAISE EXCEPTION 'FAIL: test_rls_blocks_anon: % can insert into categorias', api_role;
    EXCEPTION WHEN insufficient_privilege THEN
      NULL;
    END;

    EXECUTE 'RESET ROLE';
    RAISE NOTICE 'PASS: test_rls_blocks_anon (%)', api_role;
  END LOOP;
END
$$;

ROLLBACK;
