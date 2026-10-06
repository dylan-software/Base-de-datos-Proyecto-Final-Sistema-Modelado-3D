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

  -- La aplicacion fija el usuario con SET LOCAL app.usuario_id = '<id>';
  -- si no lo hace (por ejemplo un UPDATE manual en psql) queda en NULL.
  INSERT INTO auditoria_muebles
    (mueble_id, old_x, old_y, old_z, new_x, new_y, new_z, modificado_por)
  VALUES
    (NEW.id,
     OLD.posicion_x, OLD.posicion_y, OLD.posicion_z,
     NEW.posicion_x, NEW.posicion_y, NEW.posicion_z,
     NULLIF(current_setting('app.usuario_id', true), '')::INTEGER);

  RETURN NULL;
END;
$$;

-- AFTER UPDATE OF limita el disparo a los UPDATE que tocan alguna
-- coordenada; renombrar un mueble no genera auditoria.
CREATE TRIGGER trg_audit_muebles_cambios
  AFTER UPDATE OF posicion_x, posicion_y, posicion_z
  ON muebles_sugeridos
  FOR EACH ROW
  EXECUTE FUNCTION fn_log_mueble_movement();
