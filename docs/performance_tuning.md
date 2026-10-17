# Afinamiento de consultas y planes de ejecucion

> **OBSOLETO.** Este documento describe el esquema academico de `scripts/` (base local `modelado_3d`), que
> el backend FastAPI no usa y que es incompatible con el suyo; ver [`scripts/README.md`](../scripts/README.md).
> El esquema vigente es `schema.sql`, descrito en [`schema_fastapi.md`](schema_fastapi.md).

Este documento explica los indices de `scripts/09_performance_indexes.sql` y el costo de las politicas RLS de
`scripts/11_supabase_policies.sql`, con los planes que devolvio `EXPLAIN (ANALYZE, BUFFERS)`.

## Entorno de medicion

- PostgreSQL 17.5 (PGlite, el motor de PostgreSQL compilado a WebAssembly), en memoria.
- Carga sintetica: 200 usuarios, 2000 habitaciones de 5 x 5 m (10 por usuario) y 50 muebles por habitacion
  con `posicion_x` y `posicion_z` aleatorias: ~100 000 filas en `muebles_sugeridos`.
- `ANALYZE` antes de cada medicion para que el planificador tenga estadisticas al dia.
- El esquema `auth` de Supabase se simulo con una tabla `auth.users` y una funcion `auth.uid()` que lee
  `request.jwt.claim.sub`, igual que la de Supabase.

Los tiempos absolutos de WebAssembly no se comparan con los de un servidor real; lo que importa es la
forma del plan y las paginas leidas (`Buffers`), que si son comparables.

## Como leer `EXPLAIN ANALYZE`

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT ...;
```

| Nodo | Significado |
|---|---|
| `Seq Scan` | Lee la tabla completa y descarta las filas que no cumplen el filtro |
| `Index Scan` | Baja por el arbol B-Tree y lee solo las filas que encuentra |
| `Bitmap Index Scan` + `Bitmap Heap Scan` | Marca en un mapa de bits las paginas que contienen filas y luego las lee en orden fisico |
| `Index Cond` | Condicion que se resuelve **dentro** del indice (no lee filas que no la cumplen) |
| `Filter` / `Rows Removed by Filter` | Condicion que se evalua **despues** de leer la fila: trabajo desperdiciado |
| `InitPlan` | Subconsulta que se evalua una sola vez y se reutiliza como constante |
| `SubPlan` | Subconsulta que se evalua por fila (o se convierte en tabla hash) |
| `Buffers: shared hit/read` | Paginas de 8 kB leidas desde la cache o desde disco |

## Indice para el raycasting (`idx_muebles_habitacion_xz`)

Antes de lanzar un rayo, el visor pide solo los muebles de la franja de la planta que cruza:

```sql
SELECT id FROM muebles_sugeridos
WHERE habitacion_id = 1000
  AND posicion_x BETWEEN 1 AND 2
  AND posicion_z BETWEEN 3 AND 4;
```

Con el indice de una sola columna `idx_muebles_habitacion` (`02_indexes.sql`):

```
Bitmap Heap Scan on muebles_sugeridos (actual time=0.043..0.110 rows=1 loops=1)
  Recheck Cond: (habitacion_id = 1000)
  Filter: ((posicion_x >= 1) AND (posicion_x <= 2) AND (posicion_z >= 3) AND (posicion_z <= 4))
  Rows Removed by Filter: 49
  Heap Blocks: exact=50
  Buffers: shared hit=52
  ->  Bitmap Index Scan on idx_muebles_habitacion
        Index Cond: (habitacion_id = 1000)
```

Con el indice compuesto `(habitacion_id, posicion_x, posicion_z)`:

```
Bitmap Heap Scan on muebles_sugeridos (actual time=0.025..0.027 rows=1 loops=1)
  Recheck Cond: ((habitacion_id = 1000) AND (posicion_x >= 1) AND ... AND (posicion_z <= 4))
  Heap Blocks: exact=1
  Buffers: shared hit=1 read=3
  ->  Bitmap Index Scan on idx_muebles_habitacion_xz
        Index Cond: ((habitacion_id = 1000) AND (posicion_x >= 1) AND ... AND (posicion_z <= 4))
```

| | Filas leidas de la tabla | Paginas | Ejecucion |
|---|---|---|---|
| `idx_muebles_habitacion` | 50 (49 descartadas) | 52 | 0.137 ms |
| `idx_muebles_habitacion_xz` | 1 | 4 | 0.043 ms |

El filtro de coordenadas paso de `Filter` a `Index Cond`: las filas que no estan en la franja ya no se leen.
El costo de cargar una habitacion completa (`WHERE habitacion_id = $1`) no cambia, porque `habitacion_id` es
la primera columna del indice; por eso `idx_muebles_habitacion` quedo redundante y el script lo elimina.

**Limite del B-Tree:** el arbol solo usa como limite de busqueda la primera columna con rango
(`posicion_x`). `posicion_z` se comprueba dentro de las hojas del indice, sin ir a la tabla, pero recorre
todas las entradas de la franja X. Con pocas decenas de muebles por habitacion es suficiente; para rangos 2D
sobre millones de filas convendria un indice GiST sobre un `point` o `box`.

## Indice para el aislamiento de cuentas (`idx_habitaciones_usuario_creado`)

```sql
SELECT id, nombre FROM habitaciones WHERE usuario_id = 50 ORDER BY creado_en DESC;
```

```
Sort (actual time=0.090..0.099 rows=10 loops=1)
  Sort Key: creado_en DESC
  Sort Method: quicksort  Memory: 17kB
  ->  Bitmap Heap Scan on habitaciones
        Recheck Cond: (usuario_id = 50)
        ->  Bitmap Index Scan on idx_habitaciones_usuario_creado
              Index Cond: (usuario_id = 50)
```

Con 10 habitaciones por usuario el plan es el mismo que con `idx_habitaciones_usuario` (12 paginas en ambos
casos): ordenar 10 filas en memoria es mas barato que recorrer el indice en orden. La segunda columna
`creado_en DESC` sirve cuando una cuenta tiene muchas habitaciones o la consulta usa `LIMIT`, porque el
indice entrega las filas ya ordenadas y el `Sort` desaparece. Como cubre todo lo que cubria el indice de una
sola columna de `04_security.sql`, ese indice se elimina para no mantener dos arboles en cada `INSERT`.

## Costo de las politicas RLS

### `habitaciones`

La politica compara `usuario_id` con una subconsulta envuelta en `(SELECT ...)`:

```
Sort (actual time=0.109..0.116 rows=10 loops=1)
  InitPlan 2
    ->  Index Scan using usuarios_auth_id_key on usuarios u
          Index Cond: (auth_id = (InitPlan 1).col1)
          InitPlan 1
            ->  Result                          -- auth.uid(), una sola vez
  ->  Bitmap Heap Scan on habitaciones
        Recheck Cond: (usuario_id = (InitPlan 2).col1)
        ->  Bitmap Index Scan on idx_habitaciones_usuario_creado
              Index Cond: (usuario_id = (InitPlan 2).col1)
Execution Time: 0.160 ms
```

`auth.uid()` y la busqueda en `usuarios` se resuelven una vez (`InitPlan`) y el resultado entra como
constante en el `Index Cond`. Si se escribe `auth.uid()` sin el `(SELECT ...)`, PostgreSQL puede evaluarla
por cada fila.

### `muebles_sugeridos`: `IN` contra `= ANY(ARRAY(...))`

La primera version de la politica usaba `habitacion_id IN (SELECT h.id FROM habitaciones h)`. Para contar
los muebles visibles (`SELECT count(*) FROM muebles_sugeridos`) el plan fue:

```
Aggregate (actual time=28.159..28.164 rows=1 loops=1)
  Buffers: shared hit=1048 read=493
  ->  Bitmap Heap Scan on muebles_sugeridos
        Filter: (ANY (habitacion_id = (hashed SubPlan 3).col1))
        Rows Removed by Filter: 99552
        ->  Bitmap Index Scan on idx_muebles_habitacion_xz (rows=100052)
```

La politica quedo como `Filter`: se leyeron los 100 052 muebles para quedarse con 500. Con
`habitacion_id = ANY (ARRAY(SELECT h.id FROM habitaciones h))`:

```
Aggregate (actual time=1.965..1.971 rows=1 loops=1)
  Buffers: shared hit=528 read=19
  InitPlan 3
    ->  Bitmap Heap Scan on habitaciones h   -- las 10 habitaciones del usuario
  ->  Bitmap Heap Scan on muebles_sugeridos (rows=500)
        Recheck Cond: (habitacion_id = ANY ((InitPlan 3).col1))
        ->  Bitmap Index Scan on idx_muebles_habitacion_xz
              Index Cond: (habitacion_id = ANY ((InitPlan 3).col1))
```

| Politica | Filas leidas | Paginas | Ejecucion |
|---|---|---|---|
| `IN (SELECT ...)` | 100 052 | 1541 | 28.3 ms |
| `= ANY (ARRAY(SELECT ...))` | 500 | 547 | 2.1 ms |

`ARRAY(...)` obliga a calcular la lista de habitaciones una sola vez y la convierte en un valor que el
indice puede usar. Cuando la consulta ya filtra por habitacion (`WHERE habitacion_id = $1`, el caso normal
del visor) ambas formas usan el indice; la diferencia aparece en los listados y reportes sin filtro.

## Vistas analiticas

`vw_resumen_espacios_por_usuario` y `vw_densidad_mobiliario` se crean con `security_invoker = true`, asi que
heredan exactamente los planes de arriba: la politica de cada tabla se agrega al `WHERE` de la vista. Sin esa
opcion la vista correria con los permisos de su dueno, que no pasa por RLS, y un usuario veria las
habitaciones de todas las cuentas.

## Reproducir

```sql
-- Plan de una consulta como lo vera un usuario de la API de Supabase
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "<uuid del usuario>", "role": "authenticated"}', true);
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM muebles_sugeridos;
ROLLBACK;
```

`SET LOCAL ROLE` y `set_config(..., true)` solo duran hasta el `ROLLBACK`, asi que la sesion del SQL Editor
vuelve a ser `postgres` al terminar.
