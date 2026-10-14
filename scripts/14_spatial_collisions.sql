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

-- Funcion de trigger: rechaza el mueble nuevo si cae a menos del radio de
-- tolerancia de otro mueble de su habitacion. El radio (en metros) llega
-- como primer argumento del trigger; sin argumento se usan 0.10 m.
-- Dos INSERT simultaneos en la misma habitacion no se ven entre si hasta
-- confirmarse, y ambos pasarian la verificacion. Por eso cada insercion
-- toma primero un bloqueo consultivo por habitacion
-- (pg_advisory_xact_lock): las inserciones de una misma habitacion se
-- validan de una en una y el bloqueo se libera al terminar la transaccion.
-- Las de habitaciones distintas no se esperan entre si.
-- Si hay choque aborta con exclusion_violation (23P01), el mismo codigo de
-- una restriccion EXCLUDE.
CREATE OR REPLACE FUNCTION fn_impedir_superposicion()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  c_clase_bloqueo  CONSTANT INTEGER := 14;
  v_radio          FLOAT := COALESCE(TG_ARGV[0]::FLOAT, 0.10);
  v_choque_id      INTEGER;
  v_choque         muebles_sugeridos%ROWTYPE;
BEGIN
  PERFORM pg_advisory_xact_lock(c_clase_bloqueo, NEW.habitacion_id);

  v_choque_id := fn_verificar_colision_mueble(
    NEW.habitacion_id, NEW.posicion_x, NEW.posicion_y, NEW.posicion_z, v_radio);

  IF v_choque_id IS NOT NULL THEN
    SELECT * INTO v_choque FROM muebles_sugeridos WHERE id = v_choque_id;

    RAISE EXCEPTION 'Mueble "%" superpuesto con "%" (id %) en la habitacion %',
                    NEW.nombre, v_choque.nombre, v_choque.id, NEW.habitacion_id
      USING ERRCODE = 'exclusion_violation',
            DETAIL = format('(%s, %s, %s) esta a %s m de (%s, %s, %s); el minimo es %s m.',
                            NEW.posicion_x, NEW.posicion_y, NEW.posicion_z,
                            round(fn_distancia_euclidiana(
                                    NEW.posicion_x, NEW.posicion_y, NEW.posicion_z,
                                    v_choque.posicion_x, v_choque.posicion_y,
                                    v_choque.posicion_z)::NUMERIC, 4),
                            v_choque.posicion_x, v_choque.posicion_y, v_choque.posicion_z,
                            v_radio),
            HINT = 'Mueve el objeto o elimina el duplicado antes de guardarlo.';
  END IF;

  RETURN NEW;
END;
$$;

-- BEFORE INSERT para rechazar la fila antes de escribirla. Solo vigila las
-- inserciones: los muebles que ya existian cuando se aplico este script no
-- se revisan, y mover un mueble con UPDATE no pasa por aqui.
-- PostgreSQL ejecuta los triggers de un mismo evento en orden alfabetico:
-- este corre antes que trg_muebles_limites_check, asi que un mueble que
-- choca y ademas sobresale de la habitacion se reporta como colision.
DROP TRIGGER IF EXISTS trg_impedir_superposicion ON muebles_sugeridos;

CREATE TRIGGER trg_impedir_superposicion
  BEFORE INSERT
  ON muebles_sugeridos
  FOR EACH ROW
  EXECUTE FUNCTION fn_impedir_superposicion('0.10');
