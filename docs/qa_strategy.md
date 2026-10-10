# Estrategia de aseguramiento de calidad

Este documento describe la suite de pruebas SQL de `scripts/qa_tests/`: que verifica, como esta escrita cada
prueba y como se valido. La suite certifica las reglas que viven dentro de la base de datos (llaves foraneas,
triggers, funciones, indices y politicas RLS), que son las que protegen los datos aunque el backend o el
frontend tengan un error.

## Alcance

| Incluido | Fuera de alcance |
|---|---|
| Restricciones e integridad referencial del esquema de `scripts/` | El esquema de `schema.sql` (tablas `furniture`, `spaces`, ...), que tiene su propio `verify.sql` |
| Triggers `trg_muebles_limites_check` y `trg_audit_muebles_cambios` | La logica del Octree y la API de OmniRoute, que calculan las coordenadas antes de llegar a la base |
| Funciones `fn_distancia_euclidiana`, `fn_calcular_volumen_*`, `fn_purgar_habitaciones_vacias` | Pruebas de carga y tiempos absolutos (ver `docs/performance_tuning.md`) |
| Uso de los indices B-Tree de `09_performance_indexes.sql` | El backend y el frontend |
| Politicas RLS de `11_supabase_policies.sql` | |

## Convenciones de cada prueba

Todas las pruebas siguen la misma estructura, para que se puedan correr en cualquier orden y sobre una base con
datos reales:

1. **Encabezado.** Comentario con lo que se prueba, el script que lo implementa, donde funciona (PostgreSQL
   local, Supabase o ambos) y los casos esperados.
2. **Transaccion aislada.** `BEGIN;` al inicio y `ROLLBACK;` al final: la prueba crea su propio usuario,
   habitaciones y muebles (nombres con prefijo `QA`) y no deja nada al terminar. La unica excepcion es
   `test_funcion_distancia_euclidiana.sql`, que solo lee.
3. **Aserciones con `ASSERT`.** Dentro de bloques `DO $$ ... $$`. Si una condicion es falsa, PL/pgSQL lanza
   `assert_failure` con un mensaje que dice que se esperaba y que se obtuvo, y la ejecucion se detiene.
4. **Errores esperados.** Un caso que debe fallar se envuelve en `BEGIN ... EXCEPTION WHEN <condicion>`. Si la
   sentencia no falla, la prueba lanza `FALLO: ...`; si falla con otro codigo, el error se propaga. Asi se
   distingue "rechazado por la regla correcta" de "rechazado por cualquier motivo".
5. **Salida.** Cada caso superado emite `RAISE NOTICE 'OK ...'` y la prueba termina con
   `OK <nombre>: todas las aserciones superadas`.

Las pruebas que dependen del esquema `auth` de Supabase (`test_rls_security_auth.sql`) se omiten en
PostgreSQL local; el orquestador `run_qa_suite.sql` lo detecta solo.

## Como se valido la suite

- La suite completa se ejecuto sobre PostgreSQL 17.5 (PGlite) despues de aplicar todos los scripts de
  `scripts/` en orden. El esquema `auth` y los roles `anon` y `authenticated` se simularon como en
  `docs/performance_tuning.md`, con los privilegios por defecto que Supabase concede sobre `public`.
- Las 8 pruebas pasaron, y el conteo de filas de `habitaciones`, `muebles_sugeridos`, `usuarios` y
  `auditoria_muebles` fue el mismo antes y despues: los `ROLLBACK` no dejan residuos.
- **Prueba de mutacion:** se desactivaron los triggers y RLS, se elimino la llave foranea
  `fk_habitaciones_usuario` y el indice `idx_muebles_habitacion_xz`, y se reemplazo la formula de distancia
  por la de Manhattan. Cada prueba afectada fallo con un mensaje que apuntaba a la regla rota; una suite que
  pasa con la regla desactivada no estaria probando nada.
- No se ejecuto contra un proyecto real de Supabase, porque requiere la cuenta del equipo.
