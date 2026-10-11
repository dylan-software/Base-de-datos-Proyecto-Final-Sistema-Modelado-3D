-- Respaldo logico por habitacion. Ejecutar despues de 13_partitioning.sql.
-- Exporta el plano 3D completo de una habitacion (medidas y muebles) como
-- texto JSON.
--
-- No reemplaza a los respaldos fisicos (pg_dump o los backups diarios de
-- Supabase): sirve para guardar o mover el layout de una sola habitacion,
-- por ejemplo antes de que la IA de OmniRoute la reorganice. Es un respaldo
-- "en caliente": la exportacion es una sola consulta, que no bloquea a los
-- demas usuarios y ve una foto consistente de la habitacion aunque alguien
-- este moviendo muebles en ese momento.

-- Empaqueta una habitacion y todos sus muebles en un texto JSON:
--   {"version": 1, "exportado_en": ..., "habitacion": {...},
--    "muebles": [{...}, ...]}
-- to_jsonb(fila) copia todas las columnas, incluidas las que agregaron
-- scripts posteriores (usuario_id, medidas de los muebles), asi que el
-- formato sigue al esquema sin tocar la funcion. Los muebles van ordenados
-- por id para que dos respaldos de la misma habitacion sin cambios sean
-- identicos (mismo checksum_md5). Si la habitacion no existe aborta con
-- no_data_found (P0002) y no registra nada.
CREATE OR REPLACE FUNCTION fn_generar_backup_json_habitacion(
  p_habitacion_id INTEGER
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_respaldo  TEXT;
BEGIN
  SELECT jsonb_build_object(
           'version',      1,
           'exportado_en', now(),
           'habitacion',   to_jsonb(h),
           'muebles',      COALESCE(
             (SELECT jsonb_agg(to_jsonb(m) - 'habitacion_id' ORDER BY m.id)
              FROM muebles_sugeridos m
              WHERE m.habitacion_id = h.id),
             '[]'::JSONB)
         )::TEXT
  INTO v_respaldo
  FROM habitaciones h
  WHERE h.id = p_habitacion_id;

  IF v_respaldo IS NULL THEN
    RAISE EXCEPTION 'La habitacion % no existe', p_habitacion_id
      USING ERRCODE = 'no_data_found';
  END IF;

  RETURN v_respaldo;
END;
$$;

-- El respaldo incluye las coordenadas de cualquier habitacion, sin importar
-- su dueno: solo el dueno de las tablas puede ejecutarlo. Como en
-- sp_maintenance.sql, se revoca EXECUTE a PUBLIC y a los roles de la API de
-- Supabase cuando existen, para que no quede publicado como RPC.
REVOKE EXECUTE ON FUNCTION fn_generar_backup_json_habitacion(INTEGER) FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION fn_generar_backup_json_habitacion(INTEGER) FROM anon, authenticated;
  END IF;
END;
$$;
