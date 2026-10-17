# scripts/ - OBSOLETE academic schema

**Do not run these files on the database of the web app.** They are kept unchanged as coursework: a
separate, local PostgreSQL design (database `modelado_3d`) with triggers, views, partitioning, pg_cron jobs
and its own QA suite. The FastAPI backend does not use it.

The schema the backend uses is `schema.sql` at the root of this repository (upgrades in `migrations/`,
checks in `verify.sql`, tests in `tests/`).

## Why it is incompatible

It reuses three table names of the backend with different columns, so the two cannot share a database:

| Table | `scripts/` | Backend (`schema.sql`) |
|---|---|---|
| `usuarios` | `nombre_usuario`, `activo`, `creado_en`; bcrypt hashes from `pgcrypto` | `nombre`, `email`, `password_hash` (scrypt, computed by the backend) |
| `habitaciones` | `usuario_id INTEGER NOT NULL` foreign key to `usuarios`, `creado_en`; no polygon | `user_id VARCHAR(64)` (the token's `sub`), `vertices JSONB` |
| `muebles_sugeridos` | sizes optional; triggers reject pieces outside the room box or within 10 cm of another | sizes required; no triggers, the backend validates layouts |

It also has no `categorias` or `muebles_catalogo`, adds RLS **policies** (`11_supabase_policies.sql`) where
the backend's schema intentionally has none, and `01_schema.sql` starts with `CREATE DATABASE` and `\c`,
which only work in `psql`, not in the Supabase SQL Editor.

If some of these files were ever run on the app's Supabase project, `verify.sql` reports it: check 2 fails
when `usuarios` has `nombre_usuario`, and check 9 lists any RLS policy.

## Documentation of this schema

The second half of the root `README.md` and every file in `docs/` except `docs/schema_fastapi.md` describe
this obsolete schema.
