-- Control de colisiones entre muebles. Ejecutar despues de
-- procedures/sp_backups.sql (requiere fn_distancia_euclidiana de
-- 06_advanced_queries.sql y el indice idx_muebles_habitacion_xz de
-- 09_performance_indexes.sql).
-- Impide que dos muebles de la misma habitacion queden con su posicion en
-- el mismo punto, o a menos de un radio de tolerancia el uno del otro.
--
-- Convencion de ejes (la misma de 07_spatial_constraints.sql):
--   X -> ancho, Y -> alto (desde el piso), Z -> profundidad.
-- La posicion de un mueble es el centro de su base, en metros.
--
-- La validacion es por proximidad de puntos, no por interseccion de cajas:
-- dos muebles chocan cuando la distancia euclidiana entre sus posiciones es
-- menor que el radio,
--   d = sqrt((x2 - x1)^2 + (y2 - y1)^2 + (z2 - z1)^2) < radio
-- El Octree del backend ya separa las cajas completas antes de guardar; la
-- base de datos es la ultima barrera contra dos muebles duplicados en las
-- mismas coordenadas (por ejemplo una peticion repetida o un INSERT manual).

-- Busca, en la habitacion p_habitacion_id, el mueble cuya posicion este a
-- menos de p_radio metros del punto (p_x, p_y, p_z). Devuelve su id (el
-- mas cercano si hay varios) o NULL si el espacio esta libre. Dos muebles
-- en exactamente las mismas coordenadas estan a distancia 0 y siempre
-- chocan.
-- p_excluir_id permite reubicar un mueble sin que choque consigo mismo:
-- se pasa su propio id para que no cuente como obstaculo.
-- Los dos BETWEEN recortan primero un cuadrado de lado 2 * radio en el
-- plano X-Z, que idx_muebles_habitacion_xz (habitacion_id, posicion_x,
-- posicion_z) resuelve sin leer toda la habitacion; la distancia exacta
-- solo se calcula para los pocos muebles que quedan dentro del cuadrado.
-- STABLE porque lee muebles_sugeridos pero no la modifica.
CREATE OR REPLACE FUNCTION fn_verificar_colision_mueble(
  p_habitacion_id  INTEGER,
  p_x              FLOAT,
  p_y              FLOAT,
  p_z              FLOAT,
  p_radio          FLOAT DEFAULT 0.10,
  p_excluir_id     INTEGER DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_mueble_id INTEGER;
BEGIN
  IF p_radio IS NULL OR p_radio <= 0 THEN
    RAISE EXCEPTION 'El radio de tolerancia debe ser mayor que 0 (se recibio %)', p_radio
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT m.id
    INTO v_mueble_id
  FROM muebles_sugeridos m
  WHERE m.habitacion_id = p_habitacion_id
    AND m.id IS DISTINCT FROM p_excluir_id
    AND m.posicion_x BETWEEN p_x - p_radio AND p_x + p_radio
    AND m.posicion_z BETWEEN p_z - p_radio AND p_z + p_radio
    AND fn_distancia_euclidiana(m.posicion_x, m.posicion_y, m.posicion_z,
                                p_x, p_y, p_z) < p_radio
  ORDER BY fn_distancia_euclidiana(m.posicion_x, m.posicion_y, m.posicion_z,
                                   p_x, p_y, p_z),
           m.id
  LIMIT 1;

  RETURN v_mueble_id;
END;
$$;

-- Ejemplo: hay algo a menos de 10 cm del centro de la habitacion 1?
-- SELECT fn_verificar_colision_mueble(1, 2.0, 0.0, 2.0) IS NOT NULL AS ocupado;
