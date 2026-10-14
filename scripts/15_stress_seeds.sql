-- Datos semilla masivos para pruebas de carga. Ejecutar despues de
-- procedures/sp_vector_math.sql.
-- Simula un hotel: muchas habitaciones parecidas, cada una con unos pocos
-- muebles, para medir con EXPLAIN (ANALYZE) los indices de
-- 09_performance_indexes.sql y los triggers que corren en cada INSERT
-- (trg_impedir_superposicion y trg_muebles_limites_check).
--
-- Convencion: X -> ancho, Y -> alto, Z -> profundidad (metros). La
-- posicion es el centro de la base del mueble. Todo queda a nombre de la
-- cuenta "sistema" de 04_security.sql, y las habitaciones se reconocen por
-- el prefijo 'Hotel Estres - ' en su nombre.
-- Para borrar la simulacion (los muebles caen por ON DELETE CASCADE):
--   DELETE FROM habitaciones WHERE nombre LIKE 'Hotel Estres - %';

-- ---------------------------------------------------------------------
-- Hotel de 20 habitaciones, numeradas de forma correlativa
-- ('Hotel Estres - Habitacion 01' a '... 20') e insertadas en ese orden,
-- de modo que sus id tambien quedan consecutivos (salvo que otra sesion
-- inserte habitaciones al mismo tiempo).
-- Todas miden 2.6 m de alto y 5 m de profundidad; el ancho rota entre
-- 4, 5 y 6 m (ancho = 4 + i mod 3) para que no todas las plantas sean
-- iguales.
-- Si el hotel ya existe el bloque no hace nada: el script se puede volver
-- a ejecutar sin duplicar habitaciones.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  c_habitaciones  CONSTANT INTEGER := 20;
  v_usuario_id    INTEGER := (SELECT id FROM usuarios WHERE nombre_usuario = 'sistema');
BEGIN
  IF EXISTS (SELECT 1 FROM habitaciones WHERE nombre LIKE 'Hotel Estres - %') THEN
    RAISE NOTICE 'El hotel de estres ya existe; no se insertan habitaciones';
    RETURN;
  END IF;

  FOR i IN 1..c_habitaciones LOOP
    INSERT INTO habitaciones (nombre, alto, ancho, profundidad, usuario_id)
    VALUES (format('Hotel Estres - Habitacion %s', lpad(i::TEXT, 2, '0')),
            2.6, 4.0 + i % 3, 5.0, v_usuario_id);
  END LOOP;

  RAISE NOTICE 'Hotel de estres: % habitaciones insertadas', c_habitaciones;
END;
$$;
