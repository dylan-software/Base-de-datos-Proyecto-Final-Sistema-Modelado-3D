-- Mantenimiento del almacenamiento: estadisticas, tuplas muertas y
-- reindexacion de los indices B-Tree. Ejecutar despues de
-- procedures/sp_maintenance.sql (y de 11_supabase_policies.sql en
-- Supabase).
-- Igual que sp_maintenance.sql, esta pensado para correr fuera del flujo
-- de la aplicacion: a mano desde el SQL Editor o programado con pg_cron.
--
-- muebles_sugeridos recibe un UPDATE cada vez que un mueble se mueve en el
-- Canvas 3D. PostgreSQL no sobrescribe la fila: escribe una version nueva y
-- deja la anterior como tupla muerta hasta que VACUUM marca su espacio como
-- reutilizable. Autovacuum lo hace solo, pero tras una sesion de la IA que
-- reubica cientos de muebles conviene revisar la tabla y refrescar las
-- estadisticas sin esperarlo.

-- Refresca las estadisticas de muebles_sugeridos y diagnostica sus tuplas
-- muertas.
-- VACUUM no puede ejecutarse dentro de una funcion ni de un procedimiento
-- (PostgreSQL lo rechaza con "VACUUM cannot be executed from a function"):
-- solo corre como sentencia de nivel superior. Por eso el procedimiento
-- hace la parte que si puede, ANALYZE, y avisa con un NOTICE cuando la
-- proporcion de tuplas muertas supera p_umbral_muertas. El VACUUM se
-- programa aparte con pg_cron, que si ejecuta cada tarea como sentencia
-- de nivel superior (ver el final del archivo).
-- n_dead_tup y n_live_tup son estimaciones del recolector de estadisticas
-- y pueden tardar unos segundos en reflejar los ultimos cambios.
CREATE OR REPLACE PROCEDURE sp_ejecutar_vacuum_analitico(
  p_umbral_muertas NUMERIC DEFAULT 0.10
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_vivas    BIGINT;
  v_muertas  BIGINT;
  v_ratio    NUMERIC;
BEGIN
  ANALYZE muebles_sugeridos;

  SELECT s.n_live_tup, s.n_dead_tup
  INTO v_vivas, v_muertas
  FROM pg_stat_user_tables s
  WHERE s.relid = 'muebles_sugeridos'::REGCLASS;

  v_ratio := v_muertas::NUMERIC / GREATEST(v_vivas + v_muertas, 1);

  RAISE NOTICE 'muebles_sugeridos: % filas vivas, % muertas (% %%)',
    v_vivas, v_muertas, round(100 * v_ratio, 2);

  IF v_ratio > p_umbral_muertas THEN
    RAISE NOTICE 'Supera el umbral de % %%: ejecutar VACUUM (ANALYZE) muebles_sugeridos;',
      round(100 * p_umbral_muertas, 2);
  END IF;
END;
$$;

-- Reconstruye los indices B-Tree cuya primera columna es una llave
-- foranea: los que usan el Canvas 3D (muebles de una habitacion, franja
-- X-Z), el panel de habitaciones y el historial de posiciones. Despues de
-- muchos UPDATE y DELETE sus paginas quedan medio vacias; REINDEX los
-- escribe de nuevo compactos. Devuelve el tamano de cada indice antes y
-- despues, en bytes. Un indice que no existe (por ejemplo si no se aplico
-- 09_performance_indexes.sql) se omite.
-- REINDEX INDEX bloquea las escrituras sobre la tabla y las lecturas que
-- usarian el indice, y dentro de una funcion los bloqueos duran hasta el
-- final de la transaccion: correrla en una ventana de poco uso. Sin
-- bloqueos, a mano y fuera de una transaccion:
--   REINDEX INDEX CONCURRENTLY idx_muebles_habitacion_xz;
CREATE OR REPLACE FUNCTION fn_reindexar_tablas_espaciales()
RETURNS TABLE (indice TEXT, bytes_antes BIGINT, bytes_despues BIGINT)
LANGUAGE plpgsql
AS $$
DECLARE
  v_nombre  TEXT;
  v_indice  REGCLASS;
BEGIN
  FOREACH v_nombre IN ARRAY ARRAY[
    'idx_muebles_habitacion_xz',
    'idx_habitaciones_usuario_creado',
    'idx_auditoria_muebles_mueble'
  ]
  LOOP
    v_indice := to_regclass(v_nombre);
    CONTINUE WHEN v_indice IS NULL;

    indice := v_nombre;
    bytes_antes := pg_relation_size(v_indice);
    EXECUTE format('REINDEX INDEX %s', v_indice);
    bytes_despues := pg_relation_size(v_indice);
    RETURN NEXT;
  END LOOP;
END;
$$;

-- Solo el dueno de las tablas debe mantenerlas (ANALYZE y REINDEX lo
-- exigen de todos modos). Como en sp_maintenance.sql, se revoca EXECUTE a
-- PUBLIC y a los roles de la API de Supabase cuando existen.
REVOKE EXECUTE ON PROCEDURE sp_ejecutar_vacuum_analitico(NUMERIC) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION fn_reindexar_tablas_espaciales() FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON PROCEDURE sp_ejecutar_vacuum_analitico(NUMERIC) FROM anon, authenticated;
    REVOKE EXECUTE ON FUNCTION fn_reindexar_tablas_espaciales() FROM anon, authenticated;
  END IF;
END;
$$;

-- Programacion con pg_cron (horas en UTC; ver docs/maintenance_guide.md):
-- SELECT cron.schedule('vacuum-muebles', '30 8 * * *',
--                      $$VACUUM (ANALYZE) muebles_sugeridos$$);
-- SELECT cron.schedule('diagnostico-muebles', '45 8 * * *',
--                      $$CALL sp_ejecutar_vacuum_analitico()$$);
-- SELECT cron.schedule('reindexar-espaciales', '0 9 * * 0',
--                      $$SELECT * FROM fn_reindexar_tablas_espaciales()$$);
