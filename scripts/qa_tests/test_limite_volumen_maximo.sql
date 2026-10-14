-- Prueba de volumen maximo: en una nave de escala industrial, un mueble
-- que llena exactamente toda la habitacion se acepta y uno que la excede
-- por 1 cm en cualquier eje se rechaza. Verifica el trigger
-- trg_muebles_limites_check de 07_spatial_constraints.sql y las funciones
-- de procedures/sp_room_analytics.sql. Funciona en PostgreSQL local y en
-- Supabase.
--
-- Nave: 120 m de ancho (X), 15 m de alto (Y), 80 m de profundidad (Z).
--   V_habitacion = 120 * 15 * 80 = 144 000 m3
-- Un bloque de las mismas medidas centrado en (60, 0, 40) ocupa
-- X [0, 120], Y [0, 15], Z [0, 80]: toca las seis caras sin salirse.
--
-- Todo corre en una transaccion que termina en ROLLBACK: no deja datos.

BEGIN;

INSERT INTO usuarios (nombre_usuario, email, password_hash)
VALUES ('qa_industrial', 'qa_industrial@modelado3d.local', 'qa-sin-login');

INSERT INTO habitaciones (nombre, alto, ancho, profundidad, usuario_id)
VALUES ('QA nave industrial', 15.0, 120.0, 80.0, currval('usuarios_id_seq'));

DO $$
DECLARE
  v_habitacion_id  INTEGER := currval('habitaciones_id_seq');
  v_mueble_id      INTEGER;
  v_caso           RECORD;
BEGIN
  -- Casos 1 a 3: el bloque de la nave 1 cm mas grande en un solo eje. Cada
  -- uno debe fallar con check_violation y nombrar el eje que se excede.
  -- Van antes del bloque valido porque ocupan su mismo centro (60, 0, 40):
  -- con el bloque ya guardado, trg_impedir_superposicion
  -- (14_spatial_collisions.sql) los rechazaria por colision antes de
  -- revisar los limites.
  FOR v_caso IN
    SELECT *
    FROM (VALUES
      ('X', 120.01, 15.0,  80.0),
      ('Y', 120.0,  15.01, 80.0),
      ('Z', 120.0,  15.0,  80.01)
    ) AS c(eje, ancho, alto, profundidad)
  LOOP
    BEGIN
      INSERT INTO muebles_sugeridos
        (habitacion_id, nombre, posicion_x, posicion_y, posicion_z, ancho, alto, profundidad)
      VALUES (v_habitacion_id, 'QA bloque excedido ' || v_caso.eje,
              60.0, 0.0, 40.0, v_caso.ancho, v_caso.alto, v_caso.profundidad);
      RAISE EXCEPTION 'FALLO: se acepto un bloque que excede el eje %', v_caso.eje;
    EXCEPTION
      WHEN check_violation THEN
        ASSERT SQLERRM LIKE '%eje ' || v_caso.eje || '%',
               format('se esperaba un error en el eje %s: %s', v_caso.eje, SQLERRM);
        RAISE NOTICE 'OK exceso de 1 cm en % rechazado', v_caso.eje;
    END;
  END LOOP;

  -- Caso 4: bloque que llena el 100 % del volumen.
  INSERT INTO muebles_sugeridos
    (habitacion_id, nombre, posicion_x, posicion_y, posicion_z, ancho, alto, profundidad)
  VALUES (v_habitacion_id, 'QA bloque total', 60.0, 0.0, 40.0, 120.0, 15.0, 80.0)
  RETURNING id INTO v_mueble_id;
  RAISE NOTICE 'OK bloque de 120 x 15 x 80 m aceptado con id %', v_mueble_id;

  ASSERT fn_calcular_volumen_util(v_habitacion_id) = 144000,
         format('volumen util %s; se esperaba 144000', fn_calcular_volumen_util(v_habitacion_id));
  ASSERT fn_calcular_volumen_mobiliario(v_habitacion_id) = 144000,
         format('volumen mobiliario %s; se esperaba 144000',
                fn_calcular_volumen_mobiliario(v_habitacion_id));
  RAISE NOTICE 'OK ocupacion volumetrica del 100 %%';

  -- Caso 5: agrandar el bloque existente con UPDATE tambien dispara la
  -- validacion (UPDATE OF ancho) y deja la fila como estaba.
  BEGIN
    UPDATE muebles_sugeridos SET ancho = 121.0 WHERE id = v_mueble_id;
    RAISE EXCEPTION 'FALLO: el UPDATE dejo el bloque fuera de la nave';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'OK UPDATE que excede el volumen rechazado';
  END;

  ASSERT (SELECT ancho FROM muebles_sugeridos WHERE id = v_mueble_id) = 120.0,
         'el bloque cambio de medidas tras un UPDATE rechazado';
  ASSERT (SELECT count(*) FROM muebles_sugeridos WHERE habitacion_id = v_habitacion_id) = 1,
         'un bloque rechazado quedo guardado';
  RAISE NOTICE 'OK test_limite_volumen_maximo: todas las aserciones superadas';
END;
$$;

ROLLBACK;
