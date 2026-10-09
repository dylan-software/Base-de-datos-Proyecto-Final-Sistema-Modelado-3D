-- Rutinas de mantenimiento de tablas. Ejecutar despues de
-- 10_analytical_views.sql.
-- Pensadas para correr fuera del flujo de la aplicacion: a mano desde el
-- SQL Editor o programadas con pg_cron (en Supabase: Database ->
-- Extensions -> pg_cron).

-- Borra las habitaciones que no tienen ningun mueble y que se crearon hace
-- mas de p_antiguedad. El margen evita borrar una habitacion recien
-- creada mientras el usuario todavia esta colocando sus primeros muebles.
-- ON DELETE CASCADE elimina tambien su historial_ia. Devuelve la cantidad
-- de habitaciones borradas.
CREATE OR REPLACE FUNCTION fn_purgar_habitaciones_vacias(
  p_antiguedad INTERVAL DEFAULT INTERVAL '7 days'
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_borradas INTEGER;
BEGIN
  DELETE FROM habitaciones h
  WHERE h.creado_en < now() - p_antiguedad
    AND NOT EXISTS (
      SELECT 1 FROM muebles_sugeridos m WHERE m.habitacion_id = h.id
    );

  GET DIAGNOSTICS v_borradas = ROW_COUNT;
  RETURN v_borradas;
END;
$$;

-- Solo el dueno de las tablas debe purgar. Supabase publica las funciones
-- de public como RPC y concede EXECUTE a anon y authenticated, por eso se
-- revoca tambien a esos roles cuando existen (en PostgreSQL local no).
REVOKE EXECUTE ON FUNCTION fn_purgar_habitaciones_vacias(INTERVAL) FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION fn_purgar_habitaciones_vacias(INTERVAL) FROM anon, authenticated;
  END IF;
END;
$$;

-- Ejecucion asincrona con pg_cron, todos los dias a las 03:00 UTC:
-- SELECT cron.schedule('purgar-habitaciones-vacias', '0 3 * * *',
--                      $$SELECT fn_purgar_habitaciones_vacias()$$);
