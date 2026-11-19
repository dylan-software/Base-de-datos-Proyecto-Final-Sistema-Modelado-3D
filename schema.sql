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
-- Tables are created in foreign-key order: usuarios, categorias, muebles_catalogo, grupos_proyecto,
-- habitaciones, muebles_sugeridos, publicaciones_proyecto. Columns added after a table first existed (user_id, vertices,
-- grupo_id, descripcion, derivado_de) use ALTER TABLE ... ADD COLUMN IF NOT EXISTS, so the file also
-- upgrades a database that already has an older version of this schema.

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

-- Folders of projects (rooms) of one account, each with a free description (migration 005).
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

-- Group of the project (NULL = "Proyectos sin grupo"), its description and the project it was derived
-- from (reserved, not used yet). The CHECK and REFERENCES are declared with their column, so they are
-- skipped together with it when the column already exists: re-running adds nothing twice.
ALTER TABLE habitaciones ADD COLUMN IF NOT EXISTS grupo_id INTEGER
  REFERENCES grupos_proyecto (id) ON DELETE SET NULL;

ALTER TABLE habitaciones ADD COLUMN IF NOT EXISTS descripcion TEXT
  CONSTRAINT ck_habitaciones_descripcion_len CHECK (char_length(descripcion) <= 1000);

ALTER TABLE habitaciones ADD COLUMN IF NOT EXISTS derivado_de INTEGER
  REFERENCES habitaciones (id) ON DELETE SET NULL;

-- The projects screen lists the projects of each group.
CREATE INDEX IF NOT EXISTS ix_habitaciones_grupo_id ON habitaciones (grupo_id);

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

-- Projects published in the social network (migration 006). Private by default: a project has no row
-- until its owner publishes it, and publica is false unless set. documento is a frozen copy in the export
-- format (habita-project v1), without personal data. Deleting a project deletes its publication.
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

-- The catalog shows one card per author (their newest public publication) and the profile page lists the
-- public publications of one author, newest first (migration 007).
CREATE INDEX IF NOT EXISTS ix_publicaciones_proyecto_autor
  ON publicaciones_proyecto (user_id, id DESC) WHERE publica;

-- Public profiles of the social network (migration 007): at most one per account. codigo is the only id
-- the API shows; nombre_visible is typed by the owner when publishing (NULL = anonymous) and is never
-- copied from usuarios.nombre.
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

-- One anonymous profile for every account that already published something and has no profile yet
-- (a no-op on an empty database and on a second run).
INSERT INTO perfiles_publicos (user_id, codigo)
SELECT authors.user_id, left(replace(gen_random_uuid()::text, '-', ''), 16)
FROM (SELECT DISTINCT user_id FROM publicaciones_proyecto) AS authors
WHERE NOT EXISTS (SELECT 1 FROM perfiles_publicos p WHERE p.user_id = authors.user_id)
ON CONFLICT DO NOTHING;

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

ALTER TABLE grupos_proyecto ENABLE ROW LEVEL SECURITY;

ALTER TABLE habitaciones ENABLE ROW LEVEL SECURITY;

ALTER TABLE muebles_sugeridos ENABLE ROW LEVEL SECURITY;

-- "Public" publications are public only through the backend, never through the REST API.
ALTER TABLE publicaciones_proyecto ENABLE ROW LEVEL SECURITY;

-- Profiles link publications of the same account: public only through the backend, never the REST API.
ALTER TABLE perfiles_publicos ENABLE ROW LEVEL SECURITY;

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

COMMENT ON TABLE categorias IS 'Furniture categories, shared by every account.';
COMMENT ON COLUMN categorias.nombre IS 'Category name as first typed; unique ignoring case (uq_categorias_nombre_lower).';

COMMENT ON TABLE muebles_catalogo IS 'Furniture each account adds to its own catalog. Sizes in CENTIMETERS.';
COMMENT ON COLUMN muebles_catalogo.user_id IS 'Owning account: the session token sub (usuarios.id as text).';
COMMENT ON COLUMN muebles_catalogo.categoria_id IS 'Category of the item (categorias.id).';
COMMENT ON COLUMN muebles_catalogo.nombre IS 'Item name, checked by the backend to be a plausible piece of furniture.';
COMMENT ON COLUMN muebles_catalogo.ancho IS 'Width in CENTIMETERS, as typed in the web form (rooms use meters).';
COMMENT ON COLUMN muebles_catalogo.alto IS 'Height in CENTIMETERS.';
COMMENT ON COLUMN muebles_catalogo.profundidad IS 'Depth in CENTIMETERS.';

COMMENT ON TABLE grupos_proyecto IS 'Folders of projects (rooms) of one account, each with a free description.';
COMMENT ON COLUMN grupos_proyecto.user_id IS 'Owning account: the session token sub (usuarios.id as text).';
COMMENT ON COLUMN grupos_proyecto.nombre IS 'Group name, plain text, 1 to 80 characters.';
COMMENT ON COLUMN grupos_proyecto.descripcion IS 'Free description (place, what was changed...), at most 1000 characters; NULL if none.';
COMMENT ON COLUMN grupos_proyecto.creado_en IS 'When the group was created.';

COMMENT ON TABLE habitaciones IS 'Rooms. Meters; the 3D y axis points up, the floor is the x/z plane.';
COMMENT ON COLUMN habitaciones.user_id IS 'Owning account: the session token sub (usuarios.id as text).';
COMMENT ON COLUMN habitaciones.nombre IS 'Room name.';
COMMENT ON COLUMN habitaciones.ancho IS 'Extent along x in meters; the bounding box of vertices when they are set.';
COMMENT ON COLUMN habitaciones.alto IS 'Ceiling height in meters (3D y axis).';
COMMENT ON COLUMN habitaciones.profundidad IS 'Extent along z in meters; the bounding box of vertices when they are set.';
COMMENT ON COLUMN habitaciones.vertices IS 'Floor polygon as [{"x": m, "y": m}, ...]; the polygon y is the 3D z axis. NULL means the rectangle [0, ancho] x [0, profundidad].';
COMMENT ON COLUMN habitaciones.grupo_id IS 'Group of the project (grupos_proyecto.id); NULL = no group. Set to NULL if the group is deleted.';
COMMENT ON COLUMN habitaciones.descripcion IS 'What was done in this project and what changed, at most 1000 characters; NULL if none.';
COMMENT ON COLUMN habitaciones.derivado_de IS 'RESERVED: project this one was derived from (habitaciones.id); not used yet. Set to NULL if that project is deleted.';

COMMENT ON TABLE muebles_sugeridos IS 'Furniture placed in a room by the AI proposal or the generated layout. Meters.';
COMMENT ON COLUMN muebles_sugeridos.habitacion_id IS 'Room the piece is placed in (habitaciones.id); deleted with the room.';
COMMENT ON COLUMN muebles_sugeridos.nombre IS 'Name of the placed piece.';
COMMENT ON COLUMN muebles_sugeridos.ancho IS 'Width along x in meters.';
COMMENT ON COLUMN muebles_sugeridos.alto IS 'Height in meters.';
COMMENT ON COLUMN muebles_sugeridos.profundidad IS 'Depth along z in meters.';
COMMENT ON COLUMN muebles_sugeridos.posicion_x IS 'Center of the footprint along x, in meters.';
COMMENT ON COLUMN muebles_sugeridos.posicion_y IS 'Height of the base above the floor, in meters (0 = on the floor).';
COMMENT ON COLUMN muebles_sugeridos.posicion_z IS 'Center of the footprint along z, in meters.';

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

COMMENT ON TABLE perfiles_publicos IS 'Public profiles of the social network: one per account, created when it first publishes. Shows no email, account id or registration name.';
COMMENT ON COLUMN perfiles_publicos.user_id IS 'Owning account: the session token sub (usuarios.id as text). One profile per account. Never shown in the API.';
COMMENT ON COLUMN perfiles_publicos.codigo IS 'Public id of the profile: 16 random characters (Python secrets, or hex from gen_random_uuid in migration 007). Never changes.';
COMMENT ON COLUMN perfiles_publicos.nombre_visible IS 'Name shown in the social network, typed by the owner when publishing, 1 to 40 characters; NULL = anonymous. Never copied from usuarios.nombre.';
COMMENT ON COLUMN perfiles_publicos.creado_en IS 'When the profile was created.';
COMMENT ON COLUMN perfiles_publicos.actualizado_en IS 'When the visible name last changed.';
