-- Migration 006: project publications for the social network ("Habita").
--
-- publicaciones_proyecto: one row per published project. A project is PRIVATE by default: it has no row
-- until its owner publishes it, and a row inserted without saying otherwise has publica = false, so the
-- catalog (which only reads publica = true) never shows it.
-- documento is a frozen copy of the project in the export file format ("habita-project" version 1),
-- built and validated by the backend when the project is published. It holds no emails, account ids,
-- room ids or item ids. Copying a publication imports this document as a new project.
--
-- The backend creates the same table at startup (create_all) and turns RLS on in
-- add_project_publication_statements (app/database/connection.py). On Render the backend creates the table
-- by itself.
--
-- Idempotent and plain SQL: running the file twice does nothing the second time. Undo with
-- rollback/006_drop_project_publications.sql (destructive).

BEGIN;

CREATE TABLE IF NOT EXISTS publicaciones_proyecto (
  id              SERIAL PRIMARY KEY,
  codigo          VARCHAR(24)  NOT NULL
                  CONSTRAINT uq_publicaciones_proyecto_codigo UNIQUE,
  user_id         VARCHAR(64)  NOT NULL,
  habitacion_id   INTEGER      NOT NULL
                  CONSTRAINT uq_publicaciones_proyecto_habitacion_id UNIQUE
                  REFERENCES habitaciones (id) ON DELETE CASCADE,
  publica         BOOLEAN      NOT NULL DEFAULT false,
  titulo          VARCHAR(120) NOT NULL,
  descripcion     TEXT NULL
                  CONSTRAINT ck_publicaciones_proyecto_descripcion_len CHECK (char_length(descripcion) <= 1000),
  documento       JSONB        NOT NULL
                  CONSTRAINT ck_publicaciones_proyecto_documento_len CHECK (length(documento::text) <= 262144),
  copias          INTEGER      NOT NULL DEFAULT 0
                  CONSTRAINT ck_publicaciones_proyecto_copias CHECK (copias >= 0),
  creada_en       TIMESTAMPTZ  NOT NULL DEFAULT now(),
  actualizada_en  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- The per-account cap counts the publications of one account.
CREATE INDEX IF NOT EXISTS ix_publicaciones_proyecto_user_id ON publicaciones_proyecto (user_id);

-- The catalog lists the public rows from the newest to the oldest.
CREATE INDEX IF NOT EXISTS ix_publicaciones_proyecto_catalogo ON publicaciones_proyecto (id DESC) WHERE publica;

-- Supabase exposes every table in "public" through its REST API. RLS without policies closes it for
-- the anon and authenticated roles; the backend owns the table and bypasses RLS (same as 003 and 005).
-- "Public" publications are public only through the backend, never through that API.
ALTER TABLE publicaciones_proyecto ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE publicaciones_proyecto IS 'Projects published in the social network. Private by default: no row, or publica = false, means not listed.';
COMMENT ON COLUMN publicaciones_proyecto.codigo IS 'Public id of the publication: 16 random URL-safe characters (Python secrets). The only id the API shows.';
COMMENT ON COLUMN publicaciones_proyecto.user_id IS 'Owning account: the session token sub (usuarios.id as text). Never shown in the API.';
COMMENT ON COLUMN publicaciones_proyecto.habitacion_id IS 'Published project (habitaciones.id), at most one publication each; deleted with the project. Never shown in the API.';
COMMENT ON COLUMN publicaciones_proyecto.publica IS 'true = listed in the catalog and copyable. false by default.';
COMMENT ON COLUMN publicaciones_proyecto.titulo IS 'Title of the publication, plain text, 1 to 120 characters.';
COMMENT ON COLUMN publicaciones_proyecto.descripcion IS 'Public description written when publishing, at most 1000 characters; NULL if none. Not the private project description.';
COMMENT ON COLUMN publicaciones_proyecto.documento IS 'Frozen copy of the project in the export format habita-project v1 (meters and cm), without personal data; at most 262144 characters.';
COMMENT ON COLUMN publicaciones_proyecto.copias IS 'How many times the publication was copied to an account.';
COMMENT ON COLUMN publicaciones_proyecto.creada_en IS 'When the project was first published.';
COMMENT ON COLUMN publicaciones_proyecto.actualizada_en IS 'When the frozen copy was last refreshed.';

COMMIT;
