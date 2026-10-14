-- Tareas de mantenimiento periodicas con pg_cron. Ejecutar despues de
-- 15_stress_seeds.sql (requiere logs_actividad y auditoria_muebles de
-- 05_audit_logs.sql).
-- La funcion de purga se crea siempre; su tarea solo se programa si la
-- extension pg_cron esta instalada. En Supabase se activa desde
-- Database -> Extensions -> pg_cron; en PostgreSQL local hace falta
-- shared_preload_libraries = 'pg_cron' en postgresql.conf y reiniciar.
-- Sin pg_cron el script no falla: avisa y la funcion se puede llamar a
-- mano.
--
-- Las horas de pg_cron son UTC. Como en 12_db_maintenance.sql, se usa la
-- ventana de 08:00 a 10:00 UTC (03:00 a 05:00 en Colombia), la de menos
-- uso. Ver las tareas programadas y sus ultimas ejecuciones:
--   SELECT jobname, schedule, command FROM cron.job ORDER BY jobname;
--   SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 20;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'pg_cron no esta instalada: se crea la funcion pero no se programa su tarea';
  END IF;
END;
$$;

-- Borra los registros de auditoria con mas de p_dias dias (30 por
-- defecto) de las dos bitacoras de 05_audit_logs.sql:
--   logs_actividad     por creado_en   (sesiones y peticiones a la API)
--   auditoria_muebles  por modificado_en (historial de posiciones 3D)
-- Devuelve una fila por tabla con el numero de filas borradas.
-- log_respaldos (procedures/sp_backups.sql) no se toca: cada fila
-- documenta un respaldo que puede seguir guardado.
-- El limite se calcula una vez con now(), asi que las dos tablas se
-- recortan en el mismo instante. Los DELETE dejan tuplas muertas que
-- recupera autovacuum (la tarea vacuum-muebles de 12_db_maintenance.sql
-- solo cubre muebles_sugeridos).
CREATE OR REPLACE FUNCTION fn_purgar_logs_auditoria(p_dias INTEGER DEFAULT 30)
RETURNS TABLE (tabla TEXT, filas_borradas BIGINT)
LANGUAGE plpgsql
AS $$
DECLARE
  v_limite TIMESTAMPTZ;
BEGIN
  IF p_dias IS NULL OR p_dias < 1 THEN
    RAISE EXCEPTION 'p_dias debe ser al menos 1 (se recibio %)', p_dias
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  v_limite := now() - make_interval(days => p_dias);

  DELETE FROM logs_actividad WHERE creado_en < v_limite;
  GET DIAGNOSTICS filas_borradas = ROW_COUNT;
  tabla := 'logs_actividad';
  RETURN NEXT;

  DELETE FROM auditoria_muebles WHERE modificado_en < v_limite;
  GET DIAGNOSTICS filas_borradas = ROW_COUNT;
  tabla := 'auditoria_muebles';
  RETURN NEXT;
END;
$$;

-- Solo el dueno de las tablas debe purgar la auditoria. Como en
-- 12_db_maintenance.sql, se revoca EXECUTE a PUBLIC y a los roles de la
-- API de Supabase cuando existen.
REVOKE EXECUTE ON FUNCTION fn_purgar_logs_auditoria(INTEGER) FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION fn_purgar_logs_auditoria(INTEGER) FROM anon, authenticated;
  END IF;
END;
$$;

-- Todos los dias a las 08:15 UTC, entre la purga de habitaciones vacias y
-- el VACUUM de 12_db_maintenance.sql. cron.schedule reemplaza la tarea si
-- ya existe una con el mismo nombre, asi que el script se puede volver a
-- ejecutar.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule('purgar-logs-auditoria', '15 8 * * *',
                          'SELECT * FROM fn_purgar_logs_auditoria(30)');
  END IF;
END;
$$;
