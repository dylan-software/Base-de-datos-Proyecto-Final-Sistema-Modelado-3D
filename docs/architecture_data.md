# Arquitectura de persistencia

> **OBSOLETO.** Este documento describe el esquema academico de `scripts/` (base local `modelado_3d`), que
> el backend FastAPI no usa y que es incompatible con el suyo; ver [`scripts/README.md`](../scripts/README.md).
> El esquema vigente es `schema.sql`, descrito en [`schema_fastapi.md`](schema_fastapi.md).
>
> Donde este documento dice `schema.sql` (con `postgis`, `vector` y las tablas `furniture`, `spaces`, ...) se
> refiere al esquema del backend Node, que ahora esta en `legacy/node-schema.sql`.

Este documento describe como la base local `modelado_3d` (carpeta `scripts/`) responde a las consultas del
visor de Three.js: que indices usa, que planes de ejecucion elige PostgreSQL y como diagnosticar problemas
con las extensiones del esquema de Supabase (`schema.sql`).

## Orden de ejecucion de los scripts

| # | Archivo | Aporta |
|---|---|---|
| 1 | `scripts/01_schema.sql` | Tablas `habitaciones`, `muebles_sugeridos`, `historial_ia` |
| 2 | `scripts/02_indexes.sql` | `idx_muebles_habitacion` |
| 3 | `scripts/03_seed.sql` | Habitacion de prueba 4x4 |
| 4 | `scripts/04_security.sql` | Usuarios, roles, sesiones, `idx_habitaciones_usuario` |
| 5 | `scripts/05_audit_logs.sql` | `logs_actividad`, `auditoria_muebles` y sus indices |
| 6 | `scripts/procedures/sp_security.sql` | `fn_validar_sesion` |
| 7 | `scripts/procedures/sp_triggers.sql` | Auditoria de movimientos |
| 8 | `scripts/06_advanced_queries.sql` | `fn_distancia_euclidiana` |
| 9 | `scripts/07_spatial_constraints.sql` | Medidas de los muebles y trigger de limites |
| 10 | `scripts/procedures/sp_room_analytics.sql` | Funciones de volumen |
| 11 | `scripts/08_extended_seeds.sql` | Oficina, dormitorio y sala de prueba |
| 12 | `scripts/09_performance_indexes.sql` | Indices compuestos; reemplaza `idx_muebles_habitacion` e `idx_habitaciones_usuario` |
| 13 | `scripts/10_analytical_views.sql` | Vistas de inventario y densidad de mobiliario |
| 14 | `scripts/procedures/sp_maintenance.sql` | `fn_purgar_habitaciones_vacias` |
| 15 | `scripts/11_supabase_policies.sql` | Politicas RLS (solo Supabase) |
| 16 | `scripts/12_db_maintenance.sql` | `sp_ejecutar_vacuum_analitico` y `fn_reindexar_tablas_espaciales` |
| 17 | `scripts/13_partitioning.sql` | `historial_ia` particionada por ano |
| 18 | `scripts/procedures/sp_backups.sql` | `log_respaldos` y respaldo JSON de habitaciones |
| 19 | `scripts/14_spatial_collisions.sql` | `fn_verificar_colision_mueble` y trigger `trg_impedir_superposicion` |
| 20 | `scripts/procedures/sp_vector_math.sql` | `fn_calcular_centro_masa_habitacion` |
| 21 | `scripts/15_stress_seeds.sql` | Hotel de estres: 20 habitaciones y 50 muebles |
| 22 | `scripts/16_cron_jobs.sql` | `fn_purgar_logs_auditoria` y su tarea de pg_cron |

Cada script depende de los anteriores; ejecutarlos en otro orden falla con "relation does not exist".

## Indices B-Tree sobre llaves foraneas

PostgreSQL crea un indice automaticamente para cada `PRIMARY KEY` y `UNIQUE`, pero **no** para las llaves
foraneas. Sin un indice, filtrar por la columna hija obliga a leer la tabla completa.

La consulta mas frecuente del visor es cargar todos los muebles de la habitacion abierta:

```sql
SELECT * FROM muebles_sugeridos WHERE habitacion_id = $1;
```

Se eligio B-Tree (el tipo por defecto de `CREATE INDEX`) porque la condicion es una igualdad sobre un
`INTEGER`: el arbol encuentra la primera entrada en O(log n) y las 50 filas de la habitacion quedan
contiguas en las hojas. GiST o GIN no aportan nada para una igualdad escalar, y Hash no sirve para los
rangos `(usuario_id, creado_en)` que usan los indices de auditoria.

### Medicion

Prueba con PostgreSQL 18 y una carga sintetica de 2000 habitaciones x 50 muebles (~100 000 filas en
`muebles_sugeridos` y otras 100 000 en `historial_ia`), con `EXPLAIN ANALYZE`:

| Consulta | Plan | Paginas leidas | Tiempo |
|---|---|---|---|
| Muebles de una habitacion, con `idx_muebles_habitacion` | Index Scan | 4 | 0.021 ms |
| La misma consulta, forzando sin indice | Seq Scan (99 967 filas descartadas) | 1032 | 4.426 ms |
| Recomendaciones de una habitacion (`historial_ia`, sin indice) | Seq Scan (99 950 filas descartadas) | 637 | 4.292 ms |

El indice reduce el trabajo unas 200 veces, y la diferencia crece de forma lineal con el tamano de la tabla
mientras que el costo del Index Scan crece de forma logaritmica.

### Efecto sobre `ON DELETE CASCADE`

Borrar una habitacion dispara una busqueda en cada tabla hija. En la misma carga:

| Tabla hija | Trigger de la llave foranea | Tiempo |
|---|---|---|
| `muebles_sugeridos` (con indice) | `fk_muebles_habitacion` | 0.138 ms |
| `historial_ia` (sin indice) | `historial_ia_habitacion_id_fkey` | 4.529 ms |

### Cobertura actual

| Llave foranea | Indice |
|---|---|
| `muebles_sugeridos.habitacion_id` | `idx_muebles_habitacion_xz (habitacion_id, posicion_x, posicion_z)` |
| `habitaciones.usuario_id` | `idx_habitaciones_usuario_creado (usuario_id, creado_en DESC)` |
| `logs_actividad.usuario_id` | `idx_logs_actividad_usuario (usuario_id, creado_en)` |
| `auditoria_muebles.mueble_id` | `idx_auditoria_muebles_mueble (mueble_id, modificado_en)` |
| `usuario_roles.usuario_id` | Cubierto por la llave primaria `(usuario_id, rol_id)` |
| `historial_ia.habitacion_id` | **Ninguno** |
| `sesiones.usuario_id` | **Ninguno** |
| `usuario_roles.rol_id` | **Ninguno** (la tabla `roles` tiene 2 filas; no se justifica) |

Pendiente: `historial_ia.habitacion_id` es el caso medido arriba y conviene indexarlo si el panel de IA
consulta el historial por habitacion. `sesiones.usuario_id` solo se recorre al borrar un usuario, porque
`fn_validar_sesion` busca por `token_hash`, que ya es `UNIQUE`.

Desde `09_performance_indexes.sql` las dos primeras llaves usan indices compuestos que empiezan por la llave
foranea, asi que las mediciones de arriba siguen valiendo. Los planes de esos indices estan en
`docs/performance_tuning.md`.

## Troubleshooting de extensiones espaciales

`schema.sql` (Supabase) necesita `postgis` y `vector`; los scripts locales solo necesitan `pgcrypto`
(`procedures/sp_security.sql`). Primero comprueba que esta disponible y que esta instalado:

```sql
-- Disponible en el servidor (paquete instalado) y version instalada en esta base
SELECT name, default_version, installed_version
FROM pg_available_extensions
WHERE name IN ('postgis', 'vector', 'pgcrypto');

-- Version completa de PostGIS y de sus librerias (GEOS, PROJ)
SELECT postgis_full_version();
```

### `extension "postgis" is not available`

El paquete no esta instalado en el servidor; `CREATE EXTENSION` no lo descarga. Instalalo para la misma
version mayor de PostgreSQL y vuelve a ejecutar el script:

- Debian/Ubuntu: `sudo apt install postgresql-16-postgis-3 postgresql-16-pgvector`
- Windows: Application Stack Builder -> Spatial Extensions -> PostGIS
- Docker: usa la imagen `postgis/postgis:16-3.4` en lugar de `postgres:16`
- Supabase: **Database -> Extensions** y activa `postgis` y `vector`

### `permission denied to create extension`

Crear `postgis` requiere un superusuario. Ejecuta el `CREATE EXTENSION` con `postgres` una sola vez; el
usuario de la aplicacion no necesita ese permiso para usar las funciones despues. (`pgcrypto` si es una
extension *trusted*: la puede crear cualquier rol con permiso `CREATE` sobre la base.)

### `function st_area(geometry) does not exist` despues de restaurar

La extension quedo en un esquema que no esta en el `search_path` (en Supabase se crea en `extensions`):

```sql
SELECT e.extname, n.nspname FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace;
ALTER DATABASE postgres SET search_path = public, extensions;
```

Reconecta la sesion para que tome el nuevo `search_path`.

### Despues de actualizar PostgreSQL o PostGIS

`pg_upgrade` copia el catalogo pero la extension puede quedar en la version anterior (`installed_version`
distinta de `default_version` en la consulta de arriba). Actualizala dentro de cada base:

```sql
SELECT postgis_extensions_upgrade();   -- PostGIS 3.x: actualiza postgis y sus extensiones hermanas
ALTER EXTENSION vector UPDATE;
```

### `could not access file "$libdir/postgis-3"`

El catalogo de la base apunta a una libreria que ya no existe en el servidor (por ejemplo, se restauro un
respaldo en un servidor sin PostGIS, o se desinstalo el paquete). Instala el mismo paquete de la seccion
anterior; no hace falta recrear la extension ni perder datos.

### Restaurar un respaldo

`pg_dump` guarda `CREATE EXTENSION`, no el codigo de la extension. El servidor destino necesita los
paquetes instalados antes de `pg_restore`; si no, las columnas `geometry` y `vector` fallan al crearse y
arrastran a las tablas `spaces` y `furniture`.
