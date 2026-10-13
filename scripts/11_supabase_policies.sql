-- Politicas de seguridad a nivel de filas (RLS) para Supabase. Ejecutar
-- despues de procedures/sp_maintenance.sql.
-- Solo funciona en Supabase: usa el esquema auth y la funcion auth.uid(),
-- que devuelve el id (UUID) del usuario del JWT de la peticion. En
-- PostgreSQL local falla con "schema auth does not exist".
--
-- Las politicas solo afectan a los roles anon y authenticated de la API
-- REST. El backend se conecta como dueno de las tablas y RLS no lo filtra.

-- habitaciones.usuario_id apunta a usuarios.id (INTEGER) y auth.uid() es
-- un UUID: auth_id enlaza cada cuenta local con su cuenta de Supabase
-- Auth. Es opcional para no romper las cuentas que ya existen (como
-- "sistema"); una cuenta sin auth_id no ve nada por la API.
ALTER TABLE usuarios
  ADD COLUMN IF NOT EXISTS auth_id UUID UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL;
