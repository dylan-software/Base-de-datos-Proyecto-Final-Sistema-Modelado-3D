-- Prueba defensiva: las llaves foraneas rechazan filas que apuntan a un
-- usuario o a una habitacion que no existen. Funciona en PostgreSQL local
-- y en Supabase.
--
-- Cubre el caso en que el backend recibe un usuario_id viejo (cuenta
-- borrada) o la IA devuelve un habitacion_id equivocado: la base debe
-- responder foreign_key_violation (SQLSTATE 23503) con el nombre de la
-- restriccion, y no guardar una fila huerfana.
--
-- Todo corre en una transaccion que termina en ROLLBACK: no deja datos.

BEGIN;

DO $$
DECLARE
  -- Ids mayores que cualquier id existente: garantizan que no hay fila.
  v_usuario_fantasma     INTEGER := (SELECT COALESCE(MAX(id), 0) + 1000 FROM usuarios);
  v_habitacion_fantasma  INTEGER := (SELECT COALESCE(MAX(id), 0) + 1000 FROM habitaciones);
  v_restriccion          TEXT;
  v_habitaciones_antes   BIGINT := (SELECT count(*) FROM habitaciones);
  v_muebles_antes        BIGINT := (SELECT count(*) FROM muebles_sugeridos);
BEGIN
  -- Caso 1: habitacion de un usuario inexistente.
  BEGIN
    INSERT INTO habitaciones (nombre, alto, ancho, profundidad, usuario_id)
    VALUES ('QA sin dueno', 2.5, 3.0, 3.0, v_usuario_fantasma);
    RAISE EXCEPTION 'FALLO: se acepto una habitacion del usuario inexistente %', v_usuario_fantasma;
  EXCEPTION
    WHEN foreign_key_violation THEN
      GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
      ASSERT v_restriccion = 'fk_habitaciones_usuario',
             format('se violo %s en lugar de fk_habitaciones_usuario', v_restriccion);
      RAISE NOTICE 'OK habitacion con usuario % rechazada por %', v_usuario_fantasma, v_restriccion;
  END;

  -- Caso 2: mueble de una habitacion inexistente. fn_check_boundaries no
  -- encuentra la habitacion y deja pasar la fila; la llave foranea es la
  -- que debe rechazarla.
  BEGIN
    INSERT INTO muebles_sugeridos (habitacion_id, nombre, posicion_x, posicion_y, posicion_z)
    VALUES (v_habitacion_fantasma, 'QA mueble huerfano', 1.0, 0.0, 1.0);
    RAISE EXCEPTION 'FALLO: se acepto un mueble de la habitacion inexistente %', v_habitacion_fantasma;
  EXCEPTION
    WHEN foreign_key_violation THEN
      GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
      ASSERT v_restriccion = 'fk_muebles_habitacion',
             format('se violo %s en lugar de fk_muebles_habitacion', v_restriccion);
      RAISE NOTICE 'OK mueble con habitacion % rechazado por %', v_habitacion_fantasma, v_restriccion;
  END;

  -- Caso 3: logs_actividad acepta usuario_id NULL (login fallido de un
  -- usuario desconocido), pero no un id que no existe.
  INSERT INTO logs_actividad (usuario_id, tipo_evento) VALUES (NULL, 'login_fallido');
  RAISE NOTICE 'OK log sin usuario aceptado';

  BEGIN
    INSERT INTO logs_actividad (usuario_id, tipo_evento) VALUES (v_usuario_fantasma, 'login');
    RAISE EXCEPTION 'FALLO: se acepto un log del usuario inexistente %', v_usuario_fantasma;
  EXCEPTION
    WHEN foreign_key_violation THEN
      RAISE NOTICE 'OK log con usuario % rechazado', v_usuario_fantasma;
  END;

  -- Ningun rechazo dejo filas a medias.
  ASSERT (SELECT count(*) FROM habitaciones) = v_habitaciones_antes,
         'cambio el numero de habitaciones tras un rechazo';
  ASSERT (SELECT count(*) FROM muebles_sugeridos) = v_muebles_antes,
         'cambio el numero de muebles tras un rechazo';
  RAISE NOTICE 'OK test_error_usuario_inexistente: todas las aserciones superadas';
END;
$$;

ROLLBACK;
