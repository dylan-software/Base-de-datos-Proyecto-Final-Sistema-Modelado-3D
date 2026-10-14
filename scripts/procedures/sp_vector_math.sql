-- Algebra vectorial tridimensional sobre las posiciones de los muebles.
-- Ejecutar despues de 14_spatial_collisions.sql.
--
-- Cada mueble se trata como un vector posicion p = (x, y, z) medido desde
-- la esquina origen de su habitacion, en metros, con la convencion de
-- 07_spatial_constraints.sql: X -> ancho, Y -> alto, Z -> profundidad.
-- Las operaciones se hacen componente a componente con agregados de SQL
-- (AVG, SUM, ...), sin extensiones: funciona igual en PostgreSQL local y
-- en Supabase.

-- Centro de masa del mobiliario de una habitacion: el promedio de los
-- vectores posicion de sus n muebles,
--   c = (1 / n) * (p1 + p2 + ... + pn)
--     = (AVG(x), AVG(y), AVG(z))
-- Supone que todos los muebles pesan lo mismo (centroide de los puntos):
-- un sofa y una lampara cuentan igual. Como la posicion es el centro de la
-- base, centro_y es la altura media de las bases, no la de los volumenes.
-- Devuelve siempre una fila; si la habitacion no tiene muebles (o no
-- existe), las coordenadas son NULL y total_muebles es 0.
-- STABLE porque lee muebles_sugeridos pero no la modifica.
CREATE OR REPLACE FUNCTION fn_calcular_centro_masa_habitacion(p_habitacion_id INTEGER)
RETURNS TABLE (centro_x FLOAT, centro_y FLOAT, centro_z FLOAT, total_muebles INTEGER)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT avg(m.posicion_x),
         avg(m.posicion_y),
         avg(m.posicion_z),
         count(*)::INTEGER
  FROM muebles_sugeridos m
  WHERE m.habitacion_id = p_habitacion_id;
END;
$$;

-- Ejemplo: centro de masa de cada habitacion frente al centro geometrico
-- de su planta. Una distancia grande indica un layout cargado hacia una
-- pared.
-- SELECT h.nombre, c.*,
--        fn_distancia_euclidiana(c.centro_x, 0, c.centro_z,
--                                h.ancho / 2, 0, h.profundidad / 2) AS desvio_m
-- FROM habitaciones h
-- CROSS JOIN LATERAL fn_calcular_centro_masa_habitacion(h.id) c;
