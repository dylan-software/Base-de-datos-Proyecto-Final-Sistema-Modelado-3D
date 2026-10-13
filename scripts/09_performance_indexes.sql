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

-- Motor de colisiones y raycasting: antes de lanzar el rayo, el visor pide
-- solo los muebles de la habitacion que caen en la franja del piso que
-- cruza el rayo (planta X-Z; la altura Y casi nunca descarta muebles).
--   SELECT ... FROM muebles_sugeridos
--   WHERE habitacion_id = $1
--     AND posicion_x BETWEEN $2 AND $3
--     AND posicion_z BETWEEN $4 AND $5;
-- habitacion_id va primero por ser igualdad; posicion_x acota el rango en
-- el arbol y posicion_z se descarta dentro del mismo indice, sin leer la
-- tabla para las filas que no pasan. Un B-Tree solo usa como limite de
-- busqueda la primera columna de rango: para rangos 2D sobre tablas muy
-- grandes conviene GiST sobre un point/box. idx_muebles_habitacion de
-- 02_indexes.sql es prefijo de este y se elimina.
CREATE INDEX IF NOT EXISTS idx_muebles_habitacion_xz
  ON muebles_sugeridos (habitacion_id, posicion_x, posicion_z);

DROP INDEX IF EXISTS idx_muebles_habitacion;
