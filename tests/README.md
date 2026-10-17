# tests/

SQL tests of `schema.sql`, run with `psql` against an **empty** PostgreSQL database (13 or newer). They
need no seed data and leave the database empty: every test runs inside `BEGIN ... ROLLBACK`. Sequences
are not rolled back, so ids keep growing between runs; that is harmless.

## Run

From the root of this repository:

```
createdb proyecto3d_test
psql -v ON_ERROR_STOP=1 -d proyecto3d_test -f tests/run_all.sql
```

Add `-h`, `-p` and `-U` (or set `PGHOST`, `PGPORT`, `PGUSER`) for a server that is not the local default.
`run_all.sql` includes the other files with `\ir`, so it also works when started from another folder.

It applies `schema.sql` twice (idempotence), then `migrations/001-004` (which must be no-ops on an
up-to-date schema), then each test, and finally shows `verify.sql`.

## Reading the result

- Each test prints `NOTICE:  PASS: <test>`, or `SKIP: <test>: <reason>` when it does not apply.
- A failure prints `ERROR:  FAIL: <test>: <reason>`, stops the run and makes `psql` exit with code 3.
- The run ends with `== all tests passed` and the `verify.sql` grid, where every row must show `ok = t`.

## Tests

| File | Checks |
|---|---|
| `test_usuarios_email_unique.sql` | a second account with the same email is rejected |
| `test_categorias_case_insensitive.sql` | `Asientos`, `asientos` and `ASIENTOS` are the same category |
| `test_catalogo_requires_categoria.sql` | a catalog item needs an existing, non-NULL category |
| `test_habitacion_cascade.sql` | deleting a room deletes its placed furniture and only that |
| `test_habitaciones_vertices_json.sql` | `vertices` returns the stored polygon unchanged; NULL is allowed |
| `test_rls_blocks_anon.sql` | `anon` and `authenticated` cannot read or write any app table |

`test_rls_blocks_anon.sql` only means something on Supabase, where those roles exist. On a plain
PostgreSQL it prints SKIP. To run it on Supabase, paste the file into the SQL Editor: it rolls back
everything it inserts. The editor may hide NOTICEs, so "Success. No rows returned" means PASS and a
`FAIL: ...` error means it failed. The other test files can be pasted the same way; `run_all.sql` cannot,
because `\ir` is a psql command.
