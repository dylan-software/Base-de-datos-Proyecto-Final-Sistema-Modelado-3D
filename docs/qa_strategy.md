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

## Matriz de cobertura

### Pruebas por objeto de la base

| Objeto | Script que lo crea | Prueba | Casos |
|---|---|---|---|
| `fn_distancia_euclidiana` | `06_advanced_queries.sql` | `test_funcion_distancia_euclidiana.sql` | (1,1,1)-(4,5,1) = 5, simetria, d(P,P) = 0, tres ejes, negativos, `NULL`, `IMMUTABLE STRICT` |
| `trg_muebles_limites_check` | `07_spatial_constraints.sql` | `test_insert_coordenadas_validas.sql` | Punto en (0,0,0), mueble en la esquina origen, mueble centrado en el origen (rechazo en X) |
| `trg_muebles_limites_check` | `07_spatial_constraints.sql` | `test_limite_volumen_maximo.sql` | Bloque de 120 x 15 x 80 m que llena la nave; exceso de 1 cm en X, Y y Z; `UPDATE` que agranda el bloque |
| `fn_calcular_volumen_util` / `_mobiliario` | `procedures/sp_room_analytics.sql` | `test_limite_volumen_maximo.sql` | 144 000 m3 de capacidad y de ocupacion (100 %) |
| `fk_habitaciones_usuario`, `fk_muebles_habitacion` | `04_security.sql`, `01_schema.sql` | `test_error_usuario_inexistente.sql` | Usuario inexistente, habitacion inexistente, nombre de la restriccion violada |
| `logs_actividad.usuario_id` | `05_audit_logs.sql` | `test_error_usuario_inexistente.sql` | `NULL` aceptado (login fallido), id inexistente rechazado |
| `trg_audit_muebles_cambios` | `procedures/sp_triggers.sql` | `test_movimiento_coordenada_old_new.sql` | `old_*`/`new_*`/`modificado_por` correctos; renombrar y repetir posicion no auditan; movimiento rechazado no audita |
| `fn_purgar_habitaciones_vacias` | `procedures/sp_maintenance.sql` | `test_limpieza_espacios_vicios.sql` | Borra vacia antigua y su `historial_ia`; conserva vacia reciente y antigua con muebles; idempotente; sin `EXECUTE` para la API |
| `idx_habitaciones_usuario_creado`, `idx_muebles_habitacion_xz` | `09_performance_indexes.sql` | `test_indice_performance_query.sql` | Son B-Tree, los redundantes no existen, el plan los usa y el primero evita el `Sort` |
| `pol_habitaciones_select_propias`, `pol_muebles_select_propios` | `11_supabase_policies.sql` | `test_rls_security_auth.sql` | Ver la matriz de aislamiento |

### Matriz de aserciones de triggers

Cada fila es una operacion sobre `muebles_sugeridos` y lo que deben hacer los dos triggers. El de limites corre
`BEFORE` y el de auditoria `AFTER`, asi que una fila rechazada nunca llega a auditarse.

| Operacion | `trg_muebles_limites_check` (BEFORE) | `trg_audit_muebles_cambios` (AFTER) | Prueba |
|---|---|---|---|
| `INSERT` dentro de la habitacion | Acepta | No dispara (solo `UPDATE`) | `test_insert_coordenadas_validas` |
| `INSERT` que toca las seis caras | Acepta (margen 1e-9) | No dispara | `test_limite_volumen_maximo` |
| `INSERT` que sobresale en X, Y o Z | `check_violation` con el eje | No dispara | `test_limite_volumen_maximo` |
| `UPDATE` de `posicion_*` valido | Acepta | 1 fila con `old_*` y `new_*` | `test_movimiento_coordenada_old_new` |
| `UPDATE` de `posicion_*` con el mismo valor | Acepta | 0 filas (`IS NOT DISTINCT FROM`) | `test_movimiento_coordenada_old_new` |
| `UPDATE` de `nombre` | No dispara (`UPDATE OF`) | No dispara (`UPDATE OF`) | `test_movimiento_coordenada_old_new` |
| `UPDATE` de `posicion_*` fuera de la habitacion | `check_violation` | 0 filas | `test_movimiento_coordenada_old_new` |
| `UPDATE` de `ancho` que excede la habitacion | `check_violation` | No dispara | `test_limite_volumen_maximo` |
| `INSERT` en una habitacion inexistente | Deja pasar (sin limites) | No dispara | `test_error_usuario_inexistente` (la rechaza la llave foranea) |

### Matriz de aislamiento en Supabase (RLS)

Lo que puede hacer cada tipo de peticion que llega a la API REST de Supabase. Las escrituras de la aplicacion
pasan por el backend, que se conecta como dueno de las tablas y no es filtrado por RLS.

| Quien hace la peticion | Rol de PostgreSQL | `SELECT` | `INSERT` | `UPDATE` | Prueba |
|---|---|---|---|---|---|
| Visitante sin sesion | `anon` | 0 filas | Rechazado (`42501`) | 0 filas | `test_rls_security_auth` (caso 1) |
| JWT valido sin cuenta enlazada en `usuarios.auth_id` | `authenticated` | 0 filas | Rechazado | 0 filas o `42501` | `test_rls_security_auth` (caso 2) |
| Usuario con cuenta enlazada | `authenticated` | Solo sus habitaciones y sus muebles | Rechazado | 0 filas | Comprobacion manual del `README.md` |
| Backend (dueno de las tablas) | `postgres` | Todas las filas | Permitido | Permitido | Todas las pruebas lo usan para crear el fixture |

"0 filas" no es un error: con RLS, una fila que la politica no permite ver simplemente no existe para esa
consulta. Por eso las pruebas crean antes un fixture como dueno; sin el, "0 filas" no distinguiria un bloqueo
de una tabla vacia.

## Ciclo de vida de una lectura: de Vercel a la politica RLS

El frontend publicado en Vercel lee las tablas directamente con `fetch` a la API REST de Supabase. Este es el
camino que sigue esa peticion y el punto donde `test_rls_security_auth.sql` la intercepta:

```
 Navegador (frontend en Vercel)       Supabase API (PostgREST)              PostgreSQL
        |                                     |                                   |
        | fetch GET /rest/v1/habitaciones     |                                   |
        |   apikey: <anon key>                |                                   |
        |   Authorization: Bearer <JWT>       |                                   |
        |   (sin sesion: solo la anon key)    |                                   |
        |------------------------------------>|                                   |
        |                                     | 1. Verifica la firma del JWT      |
        |                                     |    (firma invalida -> 401, la     |
        |                                     |     peticion no llega a la base)  |
        |                                     |                                   |
        |                                     | 2. BEGIN                          |
        |                                     |    SET LOCAL ROLE <claim "role">  |
        |                                     |      anon | authenticated         |
        |                                     |    set_config('request.jwt.claims',
        |                                     |               <claims>, true)     |
        |                                     |---------------------------------->|
        |                                     |                                   |
        |                                     | 3. SELECT * FROM habitaciones     |
        |                                     |---------------------------------->|
        |                                     |                                   |--+ RLS activo en la tabla
        |                                     |                                   |  | anon: sin politica
        |                                     |                                   |  |   -> 0 filas
        |                                     |                                   |  | authenticated:
        |                                     |                                   |  |   pol_habitaciones_select_propias
        |                                     |                                   |  |   auth.uid() = claims.sub
        |                                     |                                   |  |   -> usuarios.auth_id -> usuarios.id
        |                                     |                                   |  |   -> usuario_id = <id> (indice)
        |                                     |                                   |<-+
        |                                     |<----------------------------------| filas visibles (o ninguna)
        |                                     | 4. COMMIT                         |
        |<------------------------------------| 200 OK  [ ... ]  (lista vacia,    |
        |                                     |  no 403, si no hay permiso)       |
        |                                     |                                   |
        :                                     :                                   :
        :   La prueba reproduce los pasos 2 y 3 desde el SQL Editor:              :
        :     SET LOCAL ROLE anon;  set_config('request.jwt.claims', ...);        :
        :     SELECT count(*) ...;  ASSERT ... = 0;                               :
```

- El paso 1 lo resuelve Supabase y no se puede probar desde SQL; las pruebas empiezan en el paso 2, que es
  exactamente lo que PostgREST ejecuta dentro de la base.
- Una peticion sin sesion no recibe un error sino una lista vacia. Por eso el frontend no debe interpretar
  `[]` como "el usuario no tiene habitaciones" sin comprobar antes que hay sesion.
- Las escrituras no siguen este camino: van al backend, que valida el token con `fn_validar_sesion` y se
  conecta como dueno de las tablas (ver el diagrama de autenticacion del `README.md`).

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
