-- Migration 005: project groups (folders) and descriptions on rooms.
--
-- grupos_proyecto: folders of projects, one set per account, each with a free description.
-- habitaciones.grupo_id: the folder of a project (NULL = "Proyectos sin grupo").
-- habitaciones.descripcion: what was done in this project and what changed from the previous one.
-- habitaciones.derivado_de: RESERVED for the derived version ("copy this test"); not used yet.
--
-- The backend applies the same changes at startup (add_project_group_columns in
-- app/database/connection.py), RLS included. On Render the backend creates the tables by itself.
--
-- Idempotent and plain SQL. The CHECK and FOREIGN KEY constraints are declared together with their
-- column, so ADD COLUMN IF NOT EXISTS skips them as well when the column is already there; running the
-- file twice does nothing the second time. Undo with rollback/005_drop_project_groups.sql (destructive).

BEGIN;

CREATE TABLE IF NOT EXISTS grupos_proyecto (
  id           SERIAL PRIMARY KEY,
  user_id      VARCHAR(64)  NOT NULL,
  nombre       VARCHAR(80)  NOT NULL,
  descripcion  TEXT NULL
               CONSTRAINT ck_grupos_proyecto_descripcion_len CHECK (char_length(descripcion) <= 1000),
  creado_en    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Every group query filters by the owning account.
CREATE INDEX IF NOT EXISTS ix_grupos_proyecto_user_id ON grupos_proyecto (user_id);

-- Supabase exposes every table in "public" through its REST API. RLS without policies closes it for
-- the anon and authenticated roles; the backend owns the table and bypasses RLS (same as 003).
ALTER TABLE grupos_proyecto ENABLE ROW LEVEL SECURITY;

ALTER TABLE habitaciones ADD COLUMN IF NOT EXISTS grupo_id INTEGER
  REFERENCES grupos_proyecto (id) ON DELETE SET NULL;

ALTER TABLE habitaciones ADD COLUMN IF NOT EXISTS descripcion TEXT
  CONSTRAINT ck_habitaciones_descripcion_len CHECK (char_length(descripcion) <= 1000);

-- Reserved for the derived version; no endpoint reads or writes it yet.
ALTER TABLE habitaciones ADD COLUMN IF NOT EXISTS derivado_de INTEGER
  REFERENCES habitaciones (id) ON DELETE SET NULL;

-- The projects screen lists the projects of each group.
CREATE INDEX IF NOT EXISTS ix_habitaciones_grupo_id ON habitaciones (grupo_id);

COMMENT ON TABLE grupos_proyecto IS 'Folders of projects (rooms) of one account, each with a free description.';
COMMENT ON COLUMN grupos_proyecto.user_id IS 'Owning account: the session token sub (usuarios.id as text).';
COMMENT ON COLUMN grupos_proyecto.nombre IS 'Group name, plain text, 1 to 80 characters.';
COMMENT ON COLUMN grupos_proyecto.descripcion IS 'Free description (place, what was changed...), at most 1000 characters; NULL if none.';
COMMENT ON COLUMN grupos_proyecto.creado_en IS 'When the group was created.';
COMMENT ON COLUMN habitaciones.grupo_id IS 'Group of the project (grupos_proyecto.id); NULL = no group. Set to NULL if the group is deleted.';
COMMENT ON COLUMN habitaciones.descripcion IS 'What was done in this project and what changed, at most 1000 characters; NULL if none.';
COMMENT ON COLUMN habitaciones.derivado_de IS 'RESERVED: project this one was derived from (habitaciones.id); not used yet. Set to NULL if that project is deleted.';

COMMIT;
