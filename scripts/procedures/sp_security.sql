-- Funciones de validacion de credenciales. Ejecutar despues de
-- 05_audit_logs.sql. pgcrypto aporta crypt()/gen_salt() para las firmas
-- bcrypt y digest() para el hash SHA-256 de los tokens.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- TODO: funciones de sesion.
