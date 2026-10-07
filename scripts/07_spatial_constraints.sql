-- Restricciones geometricas y espaciales. Ejecutar despues de
-- 06_advanced_queries.sql.
-- Garantiza que ningun mueble quede fuera de la caja de su habitacion.
--
-- Convencion de ejes (la misma de Three.js y de 03_seed.sql):
--   X -> ancho, Y -> alto (desde el piso), Z -> profundidad.
-- La posicion de un mueble es el centro de su base: centrado en X y Z,
-- apoyado sobre Y.

-- Medidas del mueble en metros. Son opcionales para no romper los muebles
-- existentes: si faltan, el mueble se valida como un punto.
ALTER TABLE muebles_sugeridos
  ADD COLUMN ancho        FLOAT CHECK (ancho > 0),
  ADD COLUMN alto         FLOAT CHECK (alto > 0),
  ADD COLUMN profundidad  FLOAT CHECK (profundidad > 0);

-- Funcion de trigger: compara la caja del mueble con la de su habitacion.
--   X: [x - ancho/2, x + ancho/2]        dentro de [0, habitacion.ancho]
--   Y: [y, y + alto]                     dentro de [0, habitacion.alto]
--   Z: [z - profundidad/2, z + prof./2]  dentro de [0, habitacion.profundidad]
-- COALESCE(medida, 0) reduce la caja a un punto cuando falta una medida.
-- c_eps absorbe el error de redondeo de FLOAT (2.4 + 0.6 puede no dar
-- exactamente 3.0) para que un mueble pegado a la pared no sea rechazado.
-- Si algo sobresale aborta la operacion con check_violation (23514).
CREATE OR REPLACE FUNCTION fn_check_boundaries()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  c_eps        CONSTANT FLOAT := 1e-9;
  v_hab        habitaciones%ROWTYPE;
  v_medio_x    FLOAT := COALESCE(NEW.ancho, 0) / 2;
  v_alto       FLOAT := COALESCE(NEW.alto, 0);
  v_medio_z    FLOAT := COALESCE(NEW.profundidad, 0) / 2;
BEGIN
  SELECT * INTO v_hab FROM habitaciones WHERE id = NEW.habitacion_id;

  -- Sin habitacion no hay limites que validar; la llave foranea
  -- fk_muebles_habitacion se encarga de rechazar la fila.
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  IF NEW.posicion_x - v_medio_x < -c_eps OR NEW.posicion_x + v_medio_x > v_hab.ancho + c_eps THEN
    RAISE EXCEPTION 'Mueble "%" fuera de la habitacion % en el eje X', NEW.nombre, v_hab.id
      USING ERRCODE = 'check_violation',
            DETAIL = format('Ocupa [%s, %s] y el ancho permitido es [0, %s].',
                            NEW.posicion_x - v_medio_x, NEW.posicion_x + v_medio_x, v_hab.ancho);
  END IF;

  IF NEW.posicion_y < -c_eps OR NEW.posicion_y + v_alto > v_hab.alto + c_eps THEN
    RAISE EXCEPTION 'Mueble "%" fuera de la habitacion % en el eje Y', NEW.nombre, v_hab.id
      USING ERRCODE = 'check_violation',
            DETAIL = format('Ocupa [%s, %s] y el alto permitido es [0, %s].',
                            NEW.posicion_y, NEW.posicion_y + v_alto, v_hab.alto);
  END IF;

  IF NEW.posicion_z - v_medio_z < -c_eps OR NEW.posicion_z + v_medio_z > v_hab.profundidad + c_eps THEN
    RAISE EXCEPTION 'Mueble "%" fuera de la habitacion % en el eje Z', NEW.nombre, v_hab.id
      USING ERRCODE = 'check_violation',
            DETAIL = format('Ocupa [%s, %s] y la profundidad permitida es [0, %s].',
                            NEW.posicion_z - v_medio_z, NEW.posicion_z + v_medio_z, v_hab.profundidad);
  END IF;

  RETURN NEW;
END;
$$;

-- BEFORE para rechazar la fila antes de escribirla. UPDATE OF limita el
-- disparo a las columnas que cambian la caja del mueble o su habitacion;
-- renombrar un mueble no vuelve a validar limites.
CREATE TRIGGER trg_muebles_limites_check
  BEFORE INSERT OR UPDATE OF habitacion_id, posicion_x, posicion_y, posicion_z,
                             ancho, alto, profundidad
  ON muebles_sugeridos
  FOR EACH ROW
  EXECUTE FUNCTION fn_check_boundaries();
