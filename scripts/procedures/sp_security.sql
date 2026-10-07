-- Funciones de validacion de credenciales. Ejecutar despues de
-- 05_audit_logs.sql. pgcrypto aporta crypt()/gen_salt() para las firmas
-- bcrypt y digest() para el hash SHA-256 de los tokens.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Devuelve el id del usuario dueno del token si la sesion sigue vigente
-- (no expirada, no revocada y con la cuenta activa); NULL en otro caso.
CREATE OR REPLACE FUNCTION fn_validar_sesion(p_token TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_usuario_id INTEGER;
BEGIN
  IF p_token IS NULL OR length(p_token) = 0 THEN
    RETURN NULL;
  END IF;

  SELECT s.usuario_id
    INTO v_usuario_id
  FROM sesiones s
  JOIN usuarios u ON u.id = s.usuario_id
  WHERE s.token_hash = encode(digest(p_token, 'sha256'), 'hex')
    AND NOT s.revocada
    AND s.expira_en > now()
    AND u.activo;

  RETURN v_usuario_id;
END;
$$;
