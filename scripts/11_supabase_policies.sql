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

-- Con RLS activo y sin politicas, anon y authenticated no ven ninguna
-- fila: se niega todo por defecto y cada politica abre solo lo necesario.
ALTER TABLE habitaciones ENABLE ROW LEVEL SECURITY;

-- Lectura solo de las habitaciones propias. La subconsulta traduce el
-- UUID del JWT al usuarios.id local. Envolverla en (SELECT ...) la vuelve
-- un InitPlan: se evalua una vez por consulta y no una vez por fila, y el
-- filtro queda como usuario_id = <constante>, que usa
-- idx_habitaciones_usuario_creado. Solo aplica al rol authenticated; anon
-- no tiene politica y sigue sin ver nada.
CREATE POLICY pol_habitaciones_select_propias
  ON habitaciones
  FOR SELECT
  TO authenticated
  USING (
    usuario_id = (
      SELECT u.id FROM usuarios u WHERE u.auth_id = (SELECT auth.uid())
    )
  );

-- Muebles: mismo aislamiento, heredado de la habitacion. La subconsulta
-- sobre habitaciones pasa a su vez por pol_habitaciones_select_propias,
-- asi que solo devuelve ids de habitaciones del usuario y no hace falta
-- repetir la traduccion auth.uid() -> usuarios.id.
-- Se usa = ANY(ARRAY(...)) y no IN (...): el ARRAY se calcula una vez como
-- InitPlan y queda como condicion de idx_muebles_habitacion_xz. Con IN el
-- planificador lo aplica como filtro y recorre todos los muebles de la
-- tabla (ver docs/performance_tuning.md).
ALTER TABLE muebles_sugeridos ENABLE ROW LEVEL SECURITY;

CREATE POLICY pol_muebles_select_propios
  ON muebles_sugeridos
  FOR SELECT
  TO authenticated
  USING (habitacion_id = ANY (ARRAY(SELECT h.id FROM habitaciones h)));
