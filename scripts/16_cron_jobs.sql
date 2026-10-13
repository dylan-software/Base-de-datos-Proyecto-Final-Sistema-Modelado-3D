-- Tareas de mantenimiento periodicas con pg_cron. Ejecutar despues de
-- 15_stress_seeds.sql (requiere logs_actividad y auditoria_muebles de
-- 05_audit_logs.sql).
-- Las funciones se crean siempre; las tareas solo se programan si la
-- extension pg_cron esta instalada. En Supabase se activa desde
-- Database -> Extensions -> pg_cron; en PostgreSQL local hace falta
-- shared_preload_libraries = 'pg_cron' en postgresql.conf y reiniciar.
-- Sin pg_cron el script no falla: avisa y las funciones se pueden llamar
-- a mano.
--
-- Las horas de pg_cron son UTC. Como en 12_db_maintenance.sql, se usa la
-- ventana de 08:00 a 10:00 UTC (03:00 a 05:00 en Colombia), la de menos
-- uso. Ver las tareas programadas y sus ultimas ejecuciones:
--   SELECT jobname, schedule, command FROM cron.job ORDER BY jobname;
--   SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 20;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'pg_cron no esta instalada: se crean las funciones pero no se programan tareas';
  END IF;
END;
$$;
