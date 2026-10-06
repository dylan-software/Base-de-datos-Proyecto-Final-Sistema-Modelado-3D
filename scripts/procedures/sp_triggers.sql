-- Disparadores automaticos del servidor. Ejecutar despues de
-- sp_security.sql (requiere la tabla auditoria_muebles).

-- TODO: funciones de trigger.

-- Funcion de trigger: detecta si un mueble cambio de coordenadas.
-- IS DISTINCT FROM compara sin falsos negativos y ROW(...) evalua el
-- vector (x, y, z) completo de una vez.
CREATE OR REPLACE FUNCTION fn_log_mueble_movement()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF ROW(OLD.posicion_x, OLD.posicion_y, OLD.posicion_z)
     IS NOT DISTINCT FROM
     ROW(NEW.posicion_x, NEW.posicion_y, NEW.posicion_z) THEN
    RETURN NULL;
  END IF;

  RETURN NULL;
END;
$$;
