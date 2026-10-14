-- Respaldo logico por habitacion. Ejecutar despues de 13_partitioning.sql.
-- Exporta el plano 3D completo de una habitacion (medidas y muebles) como
-- texto JSON y deja constancia de cada copia en log_respaldos.
--
-- No reemplaza a los respaldos fisicos (pg_dump o los backups diarios de
-- Supabase): sirve para guardar o mover el layout de una sola habitacion,
-- por ejemplo antes de que la IA de OmniRoute la reorganice. Es un respaldo
-- "en caliente": la exportacion es una sola consulta, que no bloquea a los
-- demas usuarios y ve una foto consistente de la habitacion aunque alguien
-- este moviendo muebles en ese momento.

-- Bitacora de respaldos ejecutados. Si despues se borra la habitacion,
-- habitacion_id queda en NULL pero el registro de la copia se conserva.
-- checksum_md5 permite comprobar que un respaldo guardado fuera de la base
-- es exactamente el que se exporto.
CREATE TABLE log_respaldos (
  id             BIGSERIAL PRIMARY KEY,
  habitacion_id  INTEGER REFERENCES habitaciones(id) ON DELETE SET NULL,
  total_muebles  INTEGER NOT NULL,
  tamano_bytes   INTEGER NOT NULL,
  checksum_md5   CHAR(32) NOT NULL,
  ejecutado_por  TEXT NOT NULL DEFAULT current_user,
  ejecutado_en   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_log_respaldos_habitacion
  ON log_respaldos (habitacion_id, ejecutado_en DESC);

-- En Supabase toda tabla de public queda expuesta por la API REST. Con RLS
-- activo y sin politicas, anon y authenticated no leen ni escriben la
-- bitacora; el dueno de las tablas no es filtrado.
ALTER TABLE log_respaldos ENABLE ROW LEVEL SECURITY;

-- Registra una copia terminada en log_respaldos y devuelve el id del
-- registro. La llama fn_generar_backup_json_habitacion como ultimo paso,
-- asi que solo se escribe cuando la exportacion termino bien; y como corre
-- en la misma transaccion, si quien la llamo hace ROLLBACK el registro
-- tambien se descarta.
CREATE OR REPLACE FUNCTION fn_registrar_respaldo(
  p_habitacion_id  INTEGER,
  p_contenido      TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  v_id  BIGINT;
BEGIN
  INSERT INTO log_respaldos
    (habitacion_id, total_muebles, tamano_bytes, checksum_md5)
  VALUES
    (p_habitacion_id,
     jsonb_array_length(p_contenido::JSONB -> 'muebles'),
     octet_length(p_contenido),
     md5(p_contenido))
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

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

  PERFORM fn_registrar_respaldo(p_habitacion_id, v_respaldo);

  RETURN v_respaldo;
END;
$$;

-- El respaldo incluye las coordenadas de cualquier habitacion, sin importar
-- su dueno: solo el dueno de las tablas puede ejecutarlo. Como en
-- sp_maintenance.sql, se revoca EXECUTE a PUBLIC y a los roles de la API de
-- Supabase cuando existen, para que no quede publicado como RPC.
REVOKE EXECUTE ON FUNCTION fn_generar_backup_json_habitacion(INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION fn_registrar_respaldo(INTEGER, TEXT) FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION fn_generar_backup_json_habitacion(INTEGER) FROM anon, authenticated;
    REVOKE EXECUTE ON FUNCTION fn_registrar_respaldo(INTEGER, TEXT) FROM anon, authenticated;
  END IF;
END;
$$;
