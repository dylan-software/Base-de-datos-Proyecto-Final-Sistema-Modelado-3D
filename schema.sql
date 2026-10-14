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
