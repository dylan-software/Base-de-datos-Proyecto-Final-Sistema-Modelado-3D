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

-- Volumen ocupado por los muebles de una habitacion: suma de las cajas
-- envolventes (ancho * alto * profundidad) de cada mueble. Es aproximado:
-- un mueble con forma irregular ocupa menos que su caja, y los muebles sin
-- medidas registradas aportan 0. Devuelve 0 si la habitacion esta vacia.
CREATE OR REPLACE FUNCTION fn_calcular_volumen_mobiliario(p_habitacion_id INTEGER)
RETURNS FLOAT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_volumen FLOAT;
BEGIN
  SELECT COALESCE(SUM(m.ancho * m.alto * m.profundidad), 0)
    INTO v_volumen
  FROM muebles_sugeridos m
  WHERE m.habitacion_id = p_habitacion_id;

  RETURN v_volumen;
END;
$$;

-- Ejemplo: porcentaje de ocupacion de cada habitacion.
-- SELECT h.nombre,
--        round((100 * fn_calcular_volumen_mobiliario(h.id)
--                   / fn_calcular_volumen_util(h.id))::NUMERIC, 2) AS ocupacion_pct
-- FROM habitaciones h;
