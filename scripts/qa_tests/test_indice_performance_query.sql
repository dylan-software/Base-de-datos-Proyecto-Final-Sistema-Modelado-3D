-- Diagnostico de indices: confirma que los indices B-Tree de
-- 09_performance_indexes.sql existen y que el planificador puede usarlos
-- en las dos consultas para las que se crearon. Funciona en PostgreSQL
-- local y en Supabase. No modifica datos.
--
-- Con tablas pequenas (los datos semilla) PostgreSQL prefiere un Seq Scan
-- porque leer 10 filas seguidas es mas barato que recorrer un indice. Por
-- eso, dentro de la transaccion, se desactivan Seq Scan y Bitmap Scan:
-- asi el plan muestra si el indice cubre la forma de la consulta, que es
-- lo que se quiere auditar. Los tiempos reales con 100 000 filas estan en
-- docs/performance_tuning.md.

BEGIN;

SET LOCAL enable_seqscan = off;
SET LOCAL enable_bitmapscan = off;

DO $$
DECLARE
  v_plan  TEXT;
BEGIN
  -- Caso 1: los dos indices compuestos existen y son B-Tree.
  ASSERT (SELECT count(*)
          FROM pg_class i
          JOIN pg_am am ON am.oid = i.relam
          WHERE i.relname IN ('idx_habitaciones_usuario_creado', 'idx_muebles_habitacion_xz')
            AND am.amname = 'btree') = 2,
         'falta algun indice compuesto o no es B-Tree';
  RAISE NOTICE 'OK idx_habitaciones_usuario_creado e idx_muebles_habitacion_xz son B-Tree';

  -- Caso 2: los indices de una columna que eran su prefijo ya no existen.
  ASSERT to_regclass('idx_habitaciones_usuario') IS NULL,
         'idx_habitaciones_usuario sigue existiendo (redundante)';
  ASSERT to_regclass('idx_muebles_habitacion') IS NULL,
         'idx_muebles_habitacion sigue existiendo (redundante)';
  RAISE NOTICE 'OK indices redundantes eliminados';

  -- Caso 3: panel de habitaciones de una cuenta, de la mas reciente a la
  -- mas antigua. Debe usar el indice y salir ya ordenado (sin nodo Sort).
  EXECUTE 'EXPLAIN (FORMAT JSON)
           SELECT id, nombre FROM habitaciones
           WHERE usuario_id = 1
           ORDER BY creado_en DESC'
    INTO v_plan;

  ASSERT v_plan LIKE '%idx_habitaciones_usuario_creado%',
         format('el plan no usa idx_habitaciones_usuario_creado: %s', v_plan);
  ASSERT v_plan NOT LIKE '%"Node Type": "Sort"%',
         format('el plan ordena en memoria en lugar de leer el indice ordenado: %s', v_plan);
  RAISE NOTICE 'OK habitaciones por usuario: Index Scan sin Sort';

  -- Caso 4: franja X-Z previa al raycasting.
  EXECUTE 'EXPLAIN (FORMAT JSON)
           SELECT id, nombre FROM muebles_sugeridos
           WHERE habitacion_id = 1
             AND posicion_x BETWEEN 0 AND 2
             AND posicion_z BETWEEN 0 AND 2'
    INTO v_plan;

  ASSERT v_plan LIKE '%idx_muebles_habitacion_xz%',
         format('el plan no usa idx_muebles_habitacion_xz: %s', v_plan);
  RAISE NOTICE 'OK franja X-Z: Index Scan sobre idx_muebles_habitacion_xz';

  RAISE NOTICE 'OK test_indice_performance_query: todas las aserciones superadas';
END;
$$;

-- Planes legibles para revisarlos a mano en la pestana de resultados.
EXPLAIN
SELECT id, nombre FROM habitaciones
WHERE usuario_id = 1
ORDER BY creado_en DESC;

EXPLAIN
SELECT id, nombre FROM muebles_sugeridos
WHERE habitacion_id = 1
  AND posicion_x BETWEEN 0 AND 2
  AND posicion_z BETWEEN 0 AND 2;

ROLLBACK;
