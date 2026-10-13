-- Prueba de seguridad: un usuario no autenticado no puede saltarse las
-- politicas RLS de 11_supabase_policies.sql. Solo funciona en Supabase
-- (requiere los roles anon/authenticated y la funcion auth.uid()).
--
-- Simula las dos peticiones que llegan a la API REST sin una cuenta
-- valida:
--   1) rol anon, sin JWT de usuario (fetch sin sesion iniciada);
--   2) rol authenticated con un JWT cuyo "sub" no esta enlazado a ninguna
--      fila de usuarios.auth_id (token valido de una cuenta ajena al
--      sistema).
-- En ambos casos se espera 0 filas al leer y un rechazo al escribir.
--
-- Todo corre en una transaccion que termina en ROLLBACK: no deja datos.

BEGIN;

-- Fixture creado como dueno de las tablas (RLS no lo filtra): una cuenta,
-- una habitacion y un mueble, para que "0 filas" signifique bloqueo y no
-- tabla vacia.
INSERT INTO usuarios (nombre_usuario, email, password_hash)
VALUES ('qa_rls', 'qa_rls@modelado3d.local', 'qa-sin-login');

INSERT INTO habitaciones (nombre, alto, ancho, profundidad, usuario_id)
VALUES ('QA RLS', 2.5, 3.0, 3.0, currval('usuarios_id_seq'));

INSERT INTO muebles_sugeridos (habitacion_id, nombre, posicion_x, posicion_y, posicion_z)
VALUES (currval('habitaciones_id_seq'), 'QA silla', 1.0, 0.0, 1.0);

-- El id del dueno se guarda en una variable de la transaccion: despues
-- del cambio de rol, anon no puede leer usuarios para buscarlo.
SELECT set_config('qa.usuario_id', currval('usuarios_id_seq')::TEXT, true);

-- Precondicion: RLS activo en las dos tablas.
DO $$
BEGIN
  ASSERT (SELECT relrowsecurity FROM pg_class WHERE oid = 'habitaciones'::regclass),
         'RLS no esta activo en habitaciones';
  ASSERT (SELECT relrowsecurity FROM pg_class WHERE oid = 'muebles_sugeridos'::regclass),
         'RLS no esta activo en muebles_sugeridos';
  RAISE NOTICE 'OK precondicion: RLS activo en habitaciones y muebles_sugeridos';
END;
$$;

-- ---------------------------------------------------------------------
-- Caso 1: rol anon (peticion sin sesion).
-- ---------------------------------------------------------------------
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', '{"role": "anon"}', true);

DO $$
DECLARE
  v_habitaciones  BIGINT;
  v_muebles       BIGINT;
BEGIN
  SELECT count(*) INTO v_habitaciones FROM habitaciones;
  SELECT count(*) INTO v_muebles FROM muebles_sugeridos;

  ASSERT v_habitaciones = 0,
         format('anon ve %s habitaciones; se esperaban 0', v_habitaciones);
  ASSERT v_muebles = 0,
         format('anon ve %s muebles; se esperaban 0', v_muebles);
  RAISE NOTICE 'OK anon: lectura bloqueada (0 habitaciones, 0 muebles)';

  -- Escritura: no hay politica INSERT, asi que RLS (o la falta de GRANT)
  -- debe rechazarla con insufficient_privilege (42501).
  BEGIN
    INSERT INTO habitaciones (nombre, alto, ancho, profundidad, usuario_id)
    VALUES ('QA intrusion', 2.5, 3.0, 3.0, current_setting('qa.usuario_id')::INTEGER);
    RAISE EXCEPTION 'FALLO: anon pudo insertar en habitaciones';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'OK anon: INSERT rechazado (%)', SQLERRM;
  END;
END;
$$;

RESET ROLE;

-- ---------------------------------------------------------------------
-- Caso 2: rol authenticated con un JWT no enlazado a ninguna cuenta.
-- ---------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
                  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::TEXT,
                  true);

DO $$
DECLARE
  v_habitaciones  BIGINT;
  v_muebles       BIGINT;
  v_filas         BIGINT;
BEGIN
  SELECT count(*) INTO v_habitaciones FROM habitaciones;
  SELECT count(*) INTO v_muebles FROM muebles_sugeridos;

  ASSERT v_habitaciones = 0,
         format('JWT sin cuenta ve %s habitaciones; se esperaban 0', v_habitaciones);
  ASSERT v_muebles = 0,
         format('JWT sin cuenta ve %s muebles; se esperaban 0', v_muebles);
  RAISE NOTICE 'OK authenticated sin cuenta: lectura bloqueada';

  -- UPDATE sin politica: con el GRANT por defecto de Supabase, RLS lo
  -- convierte en 0 filas afectadas; si el GRANT fue revocado, falla con
  -- insufficient_privilege. Ambos resultados son un bloqueo valido.
  BEGIN
    UPDATE muebles_sugeridos SET posicion_x = 2.0 WHERE nombre = 'QA silla';
    GET DIAGNOSTICS v_filas = ROW_COUNT;
    ASSERT v_filas = 0,
           format('JWT sin cuenta modifico %s muebles; se esperaban 0', v_filas);
    RAISE NOTICE 'OK authenticated sin cuenta: UPDATE no afecta filas';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'OK authenticated sin cuenta: UPDATE rechazado (%)', SQLERRM;
  END;
END;
$$;

RESET ROLE;

-- Comprobacion final como dueno: el fixture sigue intacto.
DO $$
BEGIN
  ASSERT (SELECT posicion_x FROM muebles_sugeridos WHERE nombre = 'QA silla') = 1.0,
         'el mueble del fixture fue modificado a traves de RLS';
  RAISE NOTICE 'OK test_rls_security_auth: todas las aserciones superadas';
END;
$$;

ROLLBACK;
