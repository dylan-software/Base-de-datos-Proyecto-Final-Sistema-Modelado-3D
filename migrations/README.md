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

Then run `verify.sql`: every row must have `ok = true`.

The tables must already exist; if one is missing the file stops with an error and changes nothing. In that
case run `schema.sql` instead: it creates what is missing and is also safe on a database that already has
part of the schema.

Before deploying the new backend, at least 001 and 002 must be applied (or the backend must start once).
003 can be applied at any time: the backend connects as the table owner and is not affected by RLS.

## Rollback

`rollback/` undoes the migrations that can be undone. Run rollbacks in reverse order.

- `rollback/003_disable_rls.sql` turns RLS off on the five app tables. This reopens the Supabase REST API
  on them, including emails and password hashes: use it only to diagnose and re-apply 003 afterwards.
- `rollback/002_drop_habitaciones_vertices.sql` is **destructive**: it deletes every room's polygon. As
  shipped it only counts the affected rooms; the `DROP COLUMN` line is commented out and has to be enabled
  by hand after a backup. Read the warning at the top of the file.

001 and 004 have no rollback. Dropping `user_id` would lose who owns each room and catalog item, and the
backend needs the column. Comments are harmless.
