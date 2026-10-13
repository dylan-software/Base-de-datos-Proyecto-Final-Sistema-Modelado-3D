-- Metricas de ocupacion volumetrica de cada habitacion. Ejecutar despues
-- de 07_spatial_constraints.sql (usa las medidas ancho/alto/profundidad de
-- muebles_sugeridos). Todos los volumenes se expresan en metros cubicos.

-- Capacidad total de la habitacion: V = alto * ancho * profundidad.
-- Devuelve NULL si la habitacion no existe. STABLE porque lee una tabla
-- pero no la modifica.
CREATE OR REPLACE FUNCTION fn_calcular_volumen_util(p_habitacion_id INTEGER)
RETURNS FLOAT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_volumen FLOAT;
BEGIN
  SELECT h.alto * h.ancho * h.profundidad
    INTO v_volumen
  FROM habitaciones h
  WHERE h.id = p_habitacion_id;

  RETURN v_volumen;
END;
$$;
