-- Orquestador de la suite de QA. Ejecuta todas las pruebas de
-- scripts/qa_tests/ en orden y se detiene en la primera que falle.
--
-- Usa meta-comandos de psql (\ir, \if, \gset), asi que se corre con psql
-- y no en el SQL Editor de Supabase (ahi se pega cada test por separado):
--
--   psql -d modelado_3d -f scripts/qa_tests/run_qa_suite.sql
--   psql "<cadena del Session pooler de Supabase>" -f scripts/qa_tests/run_qa_suite.sql
--
-- Requiere que la base ya tenga aplicados todos los scripts de scripts/
-- (01 a 10 y procedures/). La prueba RLS solo corre si existe el esquema
-- auth, es decir, en Supabase con 11_supabase_policies.sql aplicado.
--
-- Cada test abre su propia transaccion y termina en ROLLBACK, asi que la
-- suite no deja datos. Si un ASSERT falla, ON_ERROR_STOP corta la
-- ejecucion y psql sale con codigo 3; la conexion se cierra y PostgreSQL
-- descarta la transaccion abierta.

\set ON_ERROR_STOP on
\set QUIET on
\pset pager off

\echo '== Suite de QA: modelado_3d =='

-- 1) Funciones puras: no dependen de datos.
\echo '-- [1/8] test_funcion_distancia_euclidiana'
\ir test_funcion_distancia_euclidiana.sql

-- 2) Integridad al insertar.
\echo '-- [2/8] test_insert_coordenadas_validas'
\ir test_insert_coordenadas_validas.sql

\echo '-- [3/8] test_error_usuario_inexistente'
\ir test_error_usuario_inexistente.sql

\echo '-- [4/8] test_limite_volumen_maximo'
\ir test_limite_volumen_maximo.sql

-- 3) Triggers de auditoria y rutinas de mantenimiento.
\echo '-- [5/8] test_movimiento_coordenada_old_new'
\ir test_movimiento_coordenada_old_new.sql

\echo '-- [6/8] test_limpieza_espacios_vicios'
\ir test_limpieza_espacios_vicios.sql

-- 4) Rendimiento.
\echo '-- [7/8] test_indice_performance_query'
\ir test_indice_performance_query.sql

-- 5) Seguridad RLS, solo en Supabase.
SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') AS es_supabase \gset

\if :es_supabase
  \echo '-- [8/8] test_rls_security_auth'
  \ir test_rls_security_auth.sql
\else
  \echo '-- [8/8] test_rls_security_auth: OMITIDO (no hay esquema auth; no es Supabase)'
\endif

\echo '== Suite de QA completada sin fallos =='
