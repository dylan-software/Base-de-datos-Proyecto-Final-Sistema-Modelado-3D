-- Prueba de insercion: un mueble colocado en el origen cartesiano
-- (0, 0, 0) de la habitacion se guarda tal cual y pasa el trigger
-- trg_muebles_limites_check de 07_spatial_constraints.sql.
-- Funciona en PostgreSQL local y en Supabase.
--
-- La posicion es el centro de la base del mueble (X -> ancho,
-- Y -> alto, Z -> profundidad). Por eso:
--   - un mueble sin medidas (un punto) cabe exactamente en (0, 0, 0);
--   - un mueble con medidas toca la esquina origen en (ancho/2, 0, prof/2);
--   - el mismo mueble con su centro sobre la pared X = 0 sobresale y debe
--     rechazarse.
-- Cada insercion es una sola sentencia con RETURNING, como la que hace el
-- backend al guardar las coordenadas calculadas por la IA: o se guarda la
-- fila completa o no se guarda nada.
--
-- Todo corre en una transaccion que termina en ROLLBACK: no deja datos.

BEGIN;

INSERT INTO usuarios (nombre_usuario, email, password_hash)
VALUES ('qa_origen', 'qa_origen@modelado3d.local', 'qa-sin-login');

INSERT INTO habitaciones (nombre, alto, ancho, profundidad, usuario_id)
VALUES ('QA origen', 2.5, 4.0, 4.0, currval('usuarios_id_seq'));

DO $$
DECLARE
  v_habitacion_id  INTEGER := currval('habitaciones_id_seq');
  v_mueble         muebles_sugeridos%ROWTYPE;
BEGIN
  -- Caso 1: punto en el origen exacto.
  INSERT INTO muebles_sugeridos (habitacion_id, nombre, posicion_x, posicion_y, posicion_z)
  VALUES (v_habitacion_id, 'QA punto origen', 0.0, 0.0, 0.0)
  RETURNING * INTO v_mueble;

  ASSERT (v_mueble.posicion_x, v_mueble.posicion_y, v_mueble.posicion_z) = (0.0, 0.0, 0.0),
         format('se guardo (%s, %s, %s) en lugar de (0, 0, 0)',
                v_mueble.posicion_x, v_mueble.posicion_y, v_mueble.posicion_z);
  ASSERT v_mueble.creado_en IS NOT NULL, 'creado_en no recibio su valor por defecto';
  RAISE NOTICE 'OK punto en (0, 0, 0) aceptado con id %', v_mueble.id;

  -- Caso 2: mueble de 1.0 x 0.8 x 0.6 apoyado en la esquina origen. Su
  -- caja ocupa X [0, 1.0], Y [0, 0.8], Z [0, 0.6].
  INSERT INTO muebles_sugeridos
    (habitacion_id, nombre, posicion_x, posicion_y, posicion_z, ancho, alto, profundidad)
  VALUES (v_habitacion_id, 'QA mesa esquina', 0.5, 0.0, 0.3, 1.0, 0.8, 0.6)
  RETURNING * INTO v_mueble;

  ASSERT (v_mueble.posicion_x, v_mueble.posicion_y, v_mueble.posicion_z) = (0.5, 0.0, 0.3),
         'la mesa en la esquina origen no conservo sus coordenadas';
  RAISE NOTICE 'OK mueble con medidas en la esquina origen aceptado con id %', v_mueble.id;

  -- Caso 3: la misma mesa con su centro sobre la pared X = 0 sobresale
  -- 0.5 m por X. Va en Z = 2.0 y no en (0, 0, 0) porque ahi esta el punto
  -- del caso 1: trg_impedir_superposicion (14_spatial_collisions.sql) la
  -- rechazaria por colision antes de revisar los limites.
  BEGIN
    INSERT INTO muebles_sugeridos
      (habitacion_id, nombre, posicion_x, posicion_y, posicion_z, ancho, alto, profundidad)
    VALUES (v_habitacion_id, 'QA mesa fuera', 0.0, 0.0, 2.0, 1.0, 0.8, 0.6);
    RAISE EXCEPTION 'FALLO: se acepto un mueble que sobresale de la pared X = 0';
  EXCEPTION
    WHEN check_violation THEN
      ASSERT SQLERRM LIKE '%eje X%', format('mensaje inesperado: %s', SQLERRM);
      RAISE NOTICE 'OK mueble centrado sobre la pared X = 0 rechazado: %', SQLERRM;
  END;

  -- Solo deben quedar los dos muebles validos.
  ASSERT (SELECT count(*) FROM muebles_sugeridos WHERE habitacion_id = v_habitacion_id) = 2,
         'la insercion rechazada dejo una fila parcial';
  RAISE NOTICE 'OK test_insert_coordenadas_validas: todas las aserciones superadas';
END;
$$;

ROLLBACK;
