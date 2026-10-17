-- Runs every test in this folder against an EMPTY database. psql only (uses \ir); see tests/README.md.
--
-- 1. Applies schema.sql twice: the second run must not fail, which proves it is idempotent.
-- 2. Applies migrations/001-004 on top: on an up-to-date schema they must be no-ops.
-- 3. Runs each test. Each one works inside BEGIN ... ROLLBACK, so the database stays empty, and prints
--    PASS (or SKIP) as a NOTICE. A failure raises "FAIL: <test>: <reason>" and, with ON_ERROR_STOP,
--    stops the run with a non-zero exit code.

\set ON_ERROR_STOP on
SET client_min_messages = notice;

\echo '== schema.sql, first run'
\ir ../schema.sql
\echo '== schema.sql, second run (idempotence)'
\ir ../schema.sql

\echo '== migrations on an up-to-date schema'
\ir ../migrations/001_add_user_id_columns.sql
\ir ../migrations/002_add_habitaciones_vertices.sql
\ir ../migrations/003_enable_rls.sql
\ir ../migrations/004_column_comments.sql

\echo '== tests'
\ir test_usuarios_email_unique.sql
\ir test_categorias_case_insensitive.sql
\ir test_catalogo_requires_categoria.sql
\ir test_habitacion_cascade.sql
\ir test_habitaciones_vertices_json.sql
\ir test_rls_blocks_anon.sql

\echo '== verify.sql (every row must have ok = t)'
\ir ../verify.sql

\echo '== all tests passed'
