-- Consultas analiticas de optimizacion espacial. Ejecutar al final, despues
-- de procedures/sp_triggers.sql.

-- TODO: funciones matematicas.

-- Distancia euclidiana entre dos puntos 3D (en metros):
--   d = sqrt((x2 - x1)^2 + (y2 - y1)^2 + (z2 - z1)^2)
-- IMMUTABLE porque solo depende de sus argumentos; permite usarla en
-- indices de expresion y que el planificador la precalcule.
CREATE OR REPLACE FUNCTION fn_distancia_euclidiana(
  x1 FLOAT, y1 FLOAT, z1 FLOAT,
  x2 FLOAT, y2 FLOAT, z2 FLOAT
)
RETURNS FLOAT
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
  SELECT sqrt(power(x2 - x1, 2) + power(y2 - y1, 2) + power(z2 - z1, 2));
$$;

-- Ejemplo: distancia entre cada par de muebles de una misma habitacion.
-- SELECT a.nombre, b.nombre,
--        fn_distancia_euclidiana(a.posicion_x, a.posicion_y, a.posicion_z,
--                                b.posicion_x, b.posicion_y, b.posicion_z) AS metros
-- FROM muebles_sugeridos a
-- JOIN muebles_sugeridos b ON b.habitacion_id = a.habitacion_id AND b.id > a.id;
