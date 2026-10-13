-- Indices de rendimiento para las consultas del Canvas 3D. Ejecutar
-- despues de 08_extended_seeds.sql.
-- Todos son B-Tree (el tipo por defecto de CREATE INDEX): las consultas
-- filtran por igualdad sobre la llave y por rango sobre las coordenadas.
-- IF NOT EXISTS permite volver a ejecutar el script sin error.

-- Aislamiento de cuentas: el panel lista las habitaciones del usuario de
-- la sesion, de la mas reciente a la mas antigua, y la politica RLS de
-- 11_supabase_policies.sql filtra cada lectura por usuario_id.
--   SELECT ... FROM habitaciones WHERE usuario_id = $1 ORDER BY creado_en DESC;
-- Con creado_en DESC como segunda columna el plan sale ya ordenado (sin
-- nodo Sort). El indice de una sola columna idx_habitaciones_usuario de
-- 04_security.sql es un prefijo de este, asi que sobra y se elimina.
CREATE INDEX IF NOT EXISTS idx_habitaciones_usuario_creado
  ON habitaciones (usuario_id, creado_en DESC);

DROP INDEX IF EXISTS idx_habitaciones_usuario;
