-- Canonical database schema for Supabase. Paste the whole file into the SQL Editor and run it.
--
-- It mirrors the SQLAlchemy models of the FastAPI backend (app/models/*.py), which are the source of
-- truth: same tables, columns, types and index names, so this file and the backend's create_all at
-- startup can be applied in any order without duplicating anything.
--
-- Idempotent: every statement uses IF NOT EXISTS (or is a no-op when repeated), so it is safe to run
-- again on a database that already has some or all of these objects. Plain SQL only, without psql
-- meta-commands, so it runs as is in the Supabase SQL Editor.
--
-- Tables are created in foreign-key order: usuarios, categorias, muebles_catalogo, habitaciones,
-- muebles_sugeridos.

-- Accounts of the web app (POST /api/v1/auth/register). The plain password is never stored.
CREATE TABLE IF NOT EXISTS usuarios (
  id             SERIAL PRIMARY KEY,
  nombre         VARCHAR(120) NOT NULL,
  email          VARCHAR(254) NOT NULL,
  password_hash  VARCHAR(255) NOT NULL
);

-- One account per email. The backend lowercases emails before storing them.
CREATE UNIQUE INDEX IF NOT EXISTS ix_usuarios_email ON usuarios (email);

-- Furniture categories, shared by every account.
CREATE TABLE IF NOT EXISTS categorias (
  id      SERIAL PRIMARY KEY,
  nombre  VARCHAR(60) NOT NULL
);

-- "Asientos" and "asientos" are the same category.
CREATE UNIQUE INDEX IF NOT EXISTS uq_categorias_nombre_lower ON categorias (lower(nombre));

-- Furniture each account adds to its own catalog.
CREATE TABLE IF NOT EXISTS muebles_catalogo (
  id            SERIAL PRIMARY KEY,
  categoria_id  INTEGER NOT NULL REFERENCES categorias (id),
  nombre        VARCHAR(120) NOT NULL,
  ancho         FLOAT NOT NULL,
  alto          FLOAT NOT NULL,
  profundidad   FLOAT NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_muebles_catalogo_categoria_id ON muebles_catalogo (categoria_id);

-- Owning account (the token's "sub"). A separate ALTER so databases created before the column
-- existed get it too; on a fresh database it simply adds it.
ALTER TABLE muebles_catalogo ADD COLUMN IF NOT EXISTS user_id VARCHAR(64);

-- Every catalog query filters by the owning account.
CREATE INDEX IF NOT EXISTS ix_muebles_catalogo_user_id ON muebles_catalogo (user_id);

-- Rooms. ancho/profundidad are the floor's extent along x/z and alto the ceiling height.
CREATE TABLE IF NOT EXISTS habitaciones (
  id           SERIAL PRIMARY KEY,
  nombre       VARCHAR(120) NOT NULL,
  ancho        FLOAT NOT NULL,
  alto         FLOAT NOT NULL,
  profundidad  FLOAT NOT NULL
);

-- Owning account, added the same way as muebles_catalogo.user_id.
ALTER TABLE habitaciones ADD COLUMN IF NOT EXISTS user_id VARCHAR(64);

CREATE INDEX IF NOT EXISTS ix_habitaciones_user_id ON habitaciones (user_id);

-- Irregular, editable floor polygon. NULL for rooms created by /analyze, which are rectangles.
ALTER TABLE habitaciones ADD COLUMN IF NOT EXISTS vertices JSONB;

-- Furniture placed in a room (AI proposal or generated layout). Deleting a room deletes its furniture.
CREATE TABLE IF NOT EXISTS muebles_sugeridos (
  id             SERIAL PRIMARY KEY,
  habitacion_id  INTEGER NOT NULL REFERENCES habitaciones (id) ON DELETE CASCADE,
  nombre         VARCHAR(120) NOT NULL,
  ancho          FLOAT NOT NULL,
  alto           FLOAT NOT NULL,
  profundidad    FLOAT NOT NULL,
  posicion_x     FLOAT NOT NULL,
  posicion_y     FLOAT NOT NULL,
  posicion_z     FLOAT NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_muebles_sugeridos_habitacion_id ON muebles_sugeridos (habitacion_id);

-- ---------------------------------------------------------------------------------------------
-- Row Level Security. Supabase exposes every table in "public" through its auto-generated REST API.
-- This app never uses that API: only the backend talks to the database, connected as the owner of
-- the tables, and owners bypass RLS. RLS with NO policies therefore closes the REST API completely
-- for the anon and authenticated roles while leaving the backend unaffected. Re-running is a no-op.
-- ---------------------------------------------------------------------------------------------

-- Most sensitive table: emails and password hashes.
ALTER TABLE usuarios ENABLE ROW LEVEL SECURITY;

ALTER TABLE categorias ENABLE ROW LEVEL SECURITY;

ALTER TABLE muebles_catalogo ENABLE ROW LEVEL SECURITY;

ALTER TABLE habitaciones ENABLE ROW LEVEL SECURITY;

ALTER TABLE muebles_sugeridos ENABLE ROW LEVEL SECURITY;

-- Any other table in "public" that the current role owns, such as the tables of the old Node backend
-- (furniture, projects, spaces, placed_items) if they were ever created. Tables that belong to an
-- extension (e.g. PostGIS's spatial_ref_sys) or to another role are skipped: on Supabase they cannot
-- be altered by this role. verify.sql lists whatever is left without RLS.
DO $$
DECLARE
  t regclass;
BEGIN
  FOR t IN
    SELECT c.oid::regclass
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p')
      AND NOT c.relrowsecurity
      AND pg_has_role(c.relowner, 'USAGE')
      AND NOT EXISTS (
        SELECT 1 FROM pg_depend d
        WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e'
      )
  LOOP
    EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', t);
    RAISE NOTICE 'RLS enabled on %', t;
  END LOOP;
END
$$;

-- ---------------------------------------------------------------------------------------------
-- Column documentation, visible in the Supabase Table Editor. Units differ between tables:
-- muebles_catalogo is in CENTIMETERS, habitaciones and muebles_sugeridos are in METERS.
-- ---------------------------------------------------------------------------------------------

COMMENT ON TABLE usuarios IS 'Accounts of the web app. The backend issues HS256 session tokens whose sub is usuarios.id.';
COMMENT ON COLUMN usuarios.nombre IS 'Display name entered at registration.';
COMMENT ON COLUMN usuarios.email IS 'Login email, stored trimmed and lowercased by the backend; unique.';
COMMENT ON COLUMN usuarios.password_hash IS 'scrypt$<salt hex>$<hash hex> (n = 2^14, r = 8, p = 1). Never the plain password.';
