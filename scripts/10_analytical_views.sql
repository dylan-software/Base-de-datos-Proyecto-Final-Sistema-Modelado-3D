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

-- Densidad de mobiliario por habitacion. El area util es la planta del
-- piso (ancho * profundidad, ejes X y Z); la altura no cuenta porque los
-- muebles se apoyan en el piso.
--   muebles_por_m2   = cantidad de muebles / area util
--   huella_piso_pct  = 100 * suma de (ancho * profundidad) de cada mueble
--                      / area util
-- La huella usa la caja envolvente y los muebles sin medidas aportan 0,
-- igual que fn_calcular_volumen_mobiliario. LEFT JOIN conserva las
-- habitaciones vacias con densidad 0. Las areas ya son > 0 por los CHECK
-- de 01_schema.sql, asi que no hay division por cero.
CREATE OR REPLACE VIEW vw_densidad_mobiliario
WITH (security_invoker = true) AS
SELECT
  h.id                                                   AS habitacion_id,
  h.usuario_id,
  h.nombre,
  round((h.ancho * h.profundidad)::NUMERIC, 2)           AS area_util_m2,
  COUNT(m.id)                                            AS total_muebles,
  round((COUNT(m.id) / (h.ancho * h.profundidad))::NUMERIC, 3)
                                                         AS muebles_por_m2,
  round((100 * COALESCE(SUM(m.ancho * m.profundidad), 0)
             / (h.ancho * h.profundidad))::NUMERIC, 2)   AS huella_piso_pct
FROM habitaciones h
LEFT JOIN muebles_sugeridos m ON m.habitacion_id = h.id
GROUP BY h.id;
