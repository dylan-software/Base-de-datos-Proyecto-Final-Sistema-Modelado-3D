-- Prueba de auditoria: al mover un mueble, trg_audit_muebles_cambios
-- (procedures/sp_triggers.sql) guarda en auditoria_muebles las
-- coordenadas anteriores (old_*) y las nuevas (new_*) junto con el usuario
-- de la sesion. Funciona en PostgreSQL local y en Supabase.
--
-- Casos:
--   1) mover el mueble -> 1 fila con old/new correctos y modificado_por;
--   2) renombrarlo     -> sin fila nueva (UPDATE OF solo mira posicion_*);
--   3) reescribir la misma posicion -> sin fila nueva (IS NOT DISTINCT FROM);
--   4) moverlo fuera de la habitacion -> rechazado por
--      trg_muebles_limites_check (BEFORE) y sin fila de auditoria.
--
-- Todo corre en una transaccion que termina en ROLLBACK: no deja datos.

BEGIN;

INSERT INTO usuarios (nombre_usuario, email, password_hash)
VALUES ('qa_auditoria', 'qa_auditoria@modelado3d.local', 'qa-sin-login');

INSERT INTO habitaciones (nombre, alto, ancho, profundidad, usuario_id)
VALUES ('QA auditoria', 2.5, 4.0, 4.0, currval('usuarios_id_seq'));

INSERT INTO muebles_sugeridos (habitacion_id, nombre, posicion_x, posicion_y, posicion_z)
VALUES (currval('habitaciones_id_seq'), 'QA sillon', 1.0, 0.0, 1.0);

DO $$
DECLARE
  v_usuario_id  INTEGER := currval('usuarios_id_seq');
  v_mueble_id   INTEGER := currval('muebles_sugeridos_id_seq');
  v_log         auditoria_muebles%ROWTYPE;
  v_total       BIGINT;
BEGIN
  -- Igual que el backend: el usuario de la sesion se fija para la
  -- transaccion y el trigger lo lee con current_setting().
  PERFORM set_config('app.usuario_id', v_usuario_id::TEXT, true);

  -- Caso 1: movimiento de (1, 0, 1) a (2, 0, 3).
  UPDATE muebles_sugeridos
  SET posicion_x = 2.0, posicion_z = 3.0
  WHERE id = v_mueble_id;

  SELECT count(*) INTO v_total FROM auditoria_muebles WHERE mueble_id = v_mueble_id;
  SELECT * INTO v_log FROM auditoria_muebles WHERE mueble_id = v_mueble_id;

  ASSERT v_total = 1, format('se esperaba 1 fila de auditoria y hay %s', v_total);
  ASSERT (v_log.old_x, v_log.old_y, v_log.old_z) = (1.0, 0.0, 1.0),
         format('OLD guardado (%s, %s, %s); se esperaba (1, 0, 1)',
                v_log.old_x, v_log.old_y, v_log.old_z);
  ASSERT (v_log.new_x, v_log.new_y, v_log.new_z) = (2.0, 0.0, 3.0),
         format('NEW guardado (%s, %s, %s); se esperaba (2, 0, 3)',
                v_log.new_x, v_log.new_y, v_log.new_z);
  ASSERT v_log.modificado_por = v_usuario_id,
         format('modificado_por = %s; se esperaba %s', v_log.modificado_por, v_usuario_id);
  RAISE NOTICE 'OK movimiento auditado: (1, 0, 1) -> (2, 0, 3) por el usuario %', v_usuario_id;

  -- Caso 2: renombrar no toca coordenadas.
  UPDATE muebles_sugeridos SET nombre = 'QA sillon reclinable' WHERE id = v_mueble_id;

  -- Caso 3: misma posicion reescrita.
  UPDATE muebles_sugeridos
  SET posicion_x = 2.0, posicion_y = 0.0, posicion_z = 3.0
  WHERE id = v_mueble_id;

  SELECT count(*) INTO v_total FROM auditoria_muebles WHERE mueble_id = v_mueble_id;
  ASSERT v_total = 1, format('renombrar o repetir la posicion genero %s filas extra', v_total - 1);
  RAISE NOTICE 'OK renombrar y repetir la posicion no generan auditoria';

  -- Caso 4: X = 5 queda fuera de la habitacion de 4 m de ancho.
  BEGIN
    UPDATE muebles_sugeridos SET posicion_x = 5.0 WHERE id = v_mueble_id;
    RAISE EXCEPTION 'FALLO: se acepto mover el mueble fuera de la habitacion';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'OK movimiento invalido rechazado: %', SQLERRM;
  END;

  SELECT count(*) INTO v_total FROM auditoria_muebles WHERE mueble_id = v_mueble_id;
  ASSERT v_total = 1, 'un movimiento rechazado quedo en la auditoria';
  RAISE NOTICE 'OK test_movimiento_coordenada_old_new: todas las aserciones superadas';
END;
$$;

ROLLBACK;
