# migrations/

Numbered upgrades for a database that already has the FastAPI tables, for example one where the backend
created them with `create_all` before `user_id` and `vertices` existed. A **new** Supabase project does
not need them: run `schema.sql` there, which already contains everything below.

Every file is plain SQL (no psql meta-commands), idempotent, and wrapped in its own transaction, so it can
be pasted into the Supabase SQL Editor or run with `psql -v ON_ERROR_STOP=1 -f <file>`. Running a file
twice does nothing the second time.

## Order

Apply them in number order, one at a time, after backing up the database:

| File | What it does | Backend does it too? |
|---|---|---|
| `001_add_user_id_columns.sql` | `user_id` + index on `muebles_catalogo` and `habitaciones` | yes, at startup |
| `002_add_habitaciones_vertices.sql` | `habitaciones.vertices JSONB` (floor polygon, meters) | yes, at startup |
| `003_enable_rls.sql` | RLS without policies on the five app tables and any other owned public table | **no** |
| `004_column_comments.sql` | column comments, including units (catalog in cm, rooms in m) | no |
| `005_add_project_groups.sql` | `grupos_proyecto` (folders with a description, RLS on) and `habitaciones.grupo_id`, `descripcion`, `derivado_de` (reserved), with their indexes, `ON DELETE SET NULL` links, 1000-character `CHECK`s and comments | yes, at startup, RLS included (comments: no) |
| `006_add_project_publications.sql` | `publicaciones_proyecto` (social network: private by default with `publica` false, random public `codigo`, one row per project deleted with it, frozen `habita-project` document of at most 262144 characters, copy counter), its indexes, named `CHECK`s, RLS on and comments | yes, at startup: table, indexes and RLS (comments: no) |
| `007_add_public_profiles.sql` | `perfiles_publicos` (one public profile per account: random public `codigo`, optional `nombre_visible` of 1 to 40 characters, NULL = anonymous, never copied from `usuarios.nombre`), the per-author catalog index `ix_publicaciones_proyecto_autor`, RLS on, comments, and an anonymous profile for every account that already has publications | yes, at startup: table, index, RLS and the anonymous profiles (comments: no) |

Then run `verify.sql`: every row must have `ok = true`.

The tables must already exist; if one is missing the file stops with an error and changes nothing. In that
case run `schema.sql` instead: it creates what is missing and is also safe on a database that already has
part of the schema.

Before deploying the new backend, at least 001 and 002 must be applied (or the backend must start once).
003 can be applied at any time: the backend connects as the table owner and is not affected by RLS.
005 is also applied by a backend that has project groups when it starts; running it by hand first is
harmless. Existing projects keep working: they simply have no group (`grupo_id` NULL).
006 works the same way: a backend with the social network creates the table, its indexes and its RLS at
startup. Run the file by hand anyway (before or after that startup): it is the only way to get the column
comments, which `verify.sql` check 11 requires. No project becomes public: the table starts empty.
007 needs 006 and also works the same way. It gives every account that already published something an
ANONYMOUS profile (`nombre_visible` NULL): those authors never agreed to show a name. Their publications
are grouped under that profile in the catalog. The codes come from `gen_random_uuid()` (built into
PostgreSQL 13 and newer); the backend creates later profiles with Python `secrets`.

## Rollback

`rollback/` undoes the migrations that can be undone. Run rollbacks in reverse order.

- `rollback/007_drop_public_profiles.sql` is **destructive**: it deletes every public profile (its code,
  so old profile links stop working, and the visible name) and the per-author index. Publications and
  projects stay. As shipped it only counts what would be lost; the `DROP` lines are commented out. A
  backend with profiles re-creates the table at its next startup, with new codes and anonymous names.
- `rollback/006_drop_project_publications.sql` is **destructive**: it deletes every publication of the
  social network (projects, their furniture and the copies already made stay: a copy is an ordinary
  project). As shipped it only counts what would be lost; the `DROP` lines are commented out. A backend
  with the social network re-creates the table (empty) at its next startup.
- `rollback/005_drop_project_groups.sql` is **destructive**: it deletes every project group and every
  project description (projects and their furniture stay). As shipped it only counts what would be lost;
  the `DROP` lines are commented out and have to be enabled by hand after a backup. A backend with project
  groups re-creates the table and the columns (empty) at its next startup.
- `rollback/003_disable_rls.sql` turns RLS off on the five app tables. This reopens the Supabase REST API
  on them, including emails and password hashes: use it only to diagnose and re-apply 003 afterwards.
- `rollback/002_drop_habitaciones_vertices.sql` is **destructive**: it deletes every room's polygon. As
  shipped it only counts the affected rooms; the `DROP COLUMN` line is commented out and has to be enabled
  by hand after a backup. Read the warning at the top of the file.

001 and 004 have no rollback. Dropping `user_id` would lose who owns each room and catalog item, and the
backend needs the column. Comments are harmless.
