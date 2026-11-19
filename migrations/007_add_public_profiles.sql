-- Migration 007: public profiles for the social network ("Habita").
--
-- perfiles_publicos: at most one row per account. The catalog groups the public publications by author and
-- every author has a profile page reached through codigo, a random public id. The API never shows the
-- email, the account id or usuarios.nombre: the only name shown is nombre_visible, which the owner types
-- when publishing. NULL = anonymous ("Autor anónimo").
--
-- Accounts that already have publications get an ANONYMOUS profile here (nombre_visible NULL): they never
-- agreed to show a name. The backend creates the same table at startup (create_all) and, in
-- add_public_profile_statements (app/database/connection.py), turns RLS on, creates the partial index and
-- runs the same fill. On Render the backend does all of this by itself.
--
-- Idempotent and plain SQL: running the file twice does nothing the second time. Needs migration 006.
-- gen_random_uuid() is built into PostgreSQL 13 and newer (no extension). Undo with
-- rollback/007_drop_public_profiles.sql (destructive).

BEGIN;

CREATE TABLE IF NOT EXISTS perfiles_publicos (
  id              SERIAL PRIMARY KEY,
  user_id         VARCHAR(64)  NOT NULL
                  CONSTRAINT uq_perfiles_publicos_user_id UNIQUE,
  codigo          VARCHAR(24)  NOT NULL
                  CONSTRAINT uq_perfiles_publicos_codigo UNIQUE,
  nombre_visible  VARCHAR(40)  NULL
                  CONSTRAINT ck_perfiles_publicos_nombre_visible_len
                  CHECK (char_length(nombre_visible) BETWEEN 1 AND 40),
  creado_en       TIMESTAMPTZ  NOT NULL DEFAULT now(),
  actualizado_en  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- The catalog shows one card per author (their public publication with the highest id) and the profile
-- page lists the public publications of one author, newest first.
CREATE INDEX IF NOT EXISTS ix_publicaciones_proyecto_autor
  ON publicaciones_proyecto (user_id, id DESC) WHERE publica;

-- Same as 003, 005 and 006: RLS without policies closes the Supabase REST API for anon and authenticated;
-- the backend owns the table and bypasses RLS.
ALTER TABLE perfiles_publicos ENABLE ROW LEVEL SECURITY;

-- One anonymous profile for every account that already published something and has no profile yet.
-- The code is 16 hex characters from a random UUID (accepted by the backend's ^[A-Za-z0-9_-]{16}$).
INSERT INTO perfiles_publicos (user_id, codigo)
SELECT authors.user_id, left(replace(gen_random_uuid()::text, '-', ''), 16)
FROM (SELECT DISTINCT user_id FROM publicaciones_proyecto) AS authors
WHERE NOT EXISTS (SELECT 1 FROM perfiles_publicos p WHERE p.user_id = authors.user_id)
ON CONFLICT DO NOTHING;

COMMENT ON TABLE perfiles_publicos IS 'Public profiles of the social network: one per account, created when it first publishes. Shows no email, account id or registration name.';
COMMENT ON COLUMN perfiles_publicos.user_id IS 'Owning account: the session token sub (usuarios.id as text). One profile per account. Never shown in the API.';
COMMENT ON COLUMN perfiles_publicos.codigo IS 'Public id of the profile: 16 random characters (Python secrets, or hex from gen_random_uuid in migration 007). Never changes.';
COMMENT ON COLUMN perfiles_publicos.nombre_visible IS 'Name shown in the social network, typed by the owner when publishing, 1 to 40 characters; NULL = anonymous. Never copied from usuarios.nombre.';
COMMENT ON COLUMN perfiles_publicos.creado_en IS 'When the profile was created.';
COMMENT ON COLUMN perfiles_publicos.actualizado_en IS 'When the visible name last changed.';

COMMIT;
