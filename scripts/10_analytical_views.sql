-- Vistas analiticas para reportes. Ejecutar despues de
-- 09_performance_indexes.sql.
-- Todas usan security_invoker (PostgreSQL 15+): la vista se evalua con los
-- permisos de quien la consulta, asi las politicas RLS de
-- 11_supabase_policies.sql tambien filtran los reportes. Sin esa opcion
-- la vista corre como su dueno y expondria las filas de todas las cuentas.

-- Inventario de habitaciones por cuenta. Parte de habitaciones (y no de
-- usuarios) para que con RLS activo cada usuario vea solo su propia fila
-- y no la lista de cuentas ajenas con 0 habitaciones.
CREATE OR REPLACE VIEW vw_resumen_espacios_por_usuario
WITH (security_invoker = true) AS
SELECT
  u.id                         AS usuario_id,
  u.nombre_usuario,
  COUNT(h.id)                  AS total_habitaciones,
  MAX(h.creado_en)             AS ultima_habitacion_en
FROM habitaciones h
JOIN usuarios u ON u.id = h.usuario_id
GROUP BY u.id, u.nombre_usuario;
