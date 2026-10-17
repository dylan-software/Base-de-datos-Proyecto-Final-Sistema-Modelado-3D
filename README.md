# Database — Supabase

This is NOT an application. It is the SQL of the database that the FastAPI backend uses on Supabase.

## Files
Canonical, for the web app:
- `schema.sql` — **the file to paste into Supabase.** Creates the backend's five tables (`usuarios`,
  `categorias`, `muebles_catalogo`, `habitaciones`, `muebles_sugeridos`) and their indexes exactly as the
  SQLAlchemy models define them, turns on Row Level Security and documents every column. Idempotent.
- `verify.sql` — one read-only query that checks the result; every row must have `ok = true`.
- `migrations/` — numbered upgrades (and rollbacks) for a database created before `user_id`, `vertices`
  and RLS existed. See `migrations/README.md`.
- `tests/` — SQL tests of `schema.sql`, run with `psql`. See `tests/README.md`.
- `docs/schema_fastapi.md` — entity-relationship diagram of these tables.

Not for the web app:
- `legacy/node-schema.sql` — the schema of the old Node backend (`furniture`, `projects`, `spaces`,
  `placed_items`). Obsolete, kept for reference.
- `scripts/` — an obsolete academic schema, incompatible with the backend. See `scripts/README.md`.

## Steps for a new Supabase project
1. Create a project at https://supabase.com. Choose a region and set a database password — **save it**, you need it in step 4.
2. Open **SQL Editor → New query**, paste the full contents of `schema.sql`, and click **Run**.
   It should finish with "Success. No rows returned". No extension is needed.
3. New query → paste `verify.sql` → **Run**. It returns one grid with one row per check: every row must
   show `ok = true`; the `detail` column says what is missing otherwise.
4. Click **Connect** (top of the dashboard) and copy the **Session pooler** connection string. It looks like:
   `postgres://postgres.<project-ref>:[YOUR-PASSWORD]@aws-0-<region>.pooler.supabase.com:5432/postgres`
   Replace `[YOUR-PASSWORD]` with your password. If the password contains special characters (`@ : / # ?`),
   URL-encode them. This full string is what you set as `DATABASE_URL` in the **backend**.

Run the SQL before deploying the backend. The backend also creates missing tables and columns at startup,
so the order of the two never duplicates anything, but only `schema.sql` turns on RLS and adds the column
comments.

## Upgrading an existing database
For a Supabase project that already has the backend's tables (for example, created by an older backend
before `user_id`, `vertices` or RLS existed):

1. Back up the database (**Database → Backups**, or `pg_dump`).
2. Run `migrations/001_*.sql` to `004_*.sql` in the SQL Editor, one at a time and in number order. Each one
   is idempotent and runs in its own transaction, so a file that was already applied changes nothing.
3. Run `verify.sql` and check that every row shows `ok = true`.

Running `schema.sql` instead gives the same result, because it only adds what is missing. The migrations
exist to apply and review the changes one step at a time and to undo them: `migrations/README.md` explains
each file and the rollbacks in `migrations/rollback/`.

## Why the *Session pooler* string and not "Direct connection"
Supabase's direct connection (`db.<ref>.supabase.co`) resolves to an IPv6 address only (unless you pay for the
IPv4 add-on). Render does not support outbound IPv6, and Railway does not either, so the direct string fails
there. The Session pooler is reachable over IPv4 and works with a long-lived backend like this one. Use the
direct string only if your backend host supports IPv6.

## Why Row Level Security is on
Supabase exposes every table in the `public` schema through an auto-generated REST API. This app never uses
that API — only the backend talks to the database. Enabling RLS with no policies closes that REST API door
completely, and the backend is unaffected because it connects as the table owner (owners bypass RLS).

## What was tested
`schema.sql` and the backend were run end-to-end against a real PostgreSQL 16 + PostGIS 3.4 + pgvector 0.6
(create an L-shaped space, move a vertex, create objects, generate and read back a layout), and the RLS
behaviour was checked with a restricted role. It was **not** run against a live Supabase project, since that
requires your account.

---

# Base de datos local — PostgreSQL (`scripts/`)

> **OBSOLETO.** Todo lo que sigue describe el esquema academico de `scripts/`, que el backend FastAPI no usa
> y que es incompatible con el suyo. No lo ejecutes en la base de la aplicacion: lee
> [`scripts/README.md`](scripts/README.md). El esquema vigente es `schema.sql` (seccion de arriba).

Esquema relacional independiente del de Supabase para la aplicacion web de modelado 3D. Persiste las
dimensiones de las habitaciones, las coordenadas (X, Y, Z) de los muebles validados por el Octree y el
historial de recomendaciones esteticas que devuelve la API de OmniRoute.

| Archivo | Contenido |
|---|---|
| `scripts/01_schema.sql` | Crea la base `modelado_3d` y las tablas `habitaciones`, `muebles_sugeridos`, `historial_ia` |
| `scripts/02_indexes.sql` | Indice sobre la llave foranea `muebles_sugeridos.habitacion_id` (reemplazado en `09_performance_indexes.sql`) |
| `scripts/03_seed.sql` | Habitacion vacia de 4x4 m con un sofa y un escritorio de prueba |
| `scripts/04_security.sql` | Tablas `usuarios`, `roles`, `usuario_roles`, `sesiones` y la llave foranea `habitaciones.usuario_id` |
| `scripts/05_audit_logs.sql` | Tablas `logs_actividad` y `auditoria_muebles` |
| `scripts/procedures/sp_security.sql` | Extension `pgcrypto` y la funcion `fn_validar_sesion` |
| `scripts/procedures/sp_triggers.sql` | Funcion `fn_log_mueble_movement` y trigger `trg_audit_muebles_cambios` |
| `scripts/06_advanced_queries.sql` | Funcion `fn_distancia_euclidiana` para calculos espaciales |
| `scripts/07_spatial_constraints.sql` | Medidas `ancho/alto/profundidad` de cada mueble, `fn_check_boundaries` y trigger `trg_muebles_limites_check` |
| `scripts/procedures/sp_room_analytics.sql` | Funciones `fn_calcular_volumen_util` y `fn_calcular_volumen_mobiliario` |
| `scripts/08_extended_seeds.sql` | Escenarios de prueba: oficina, dormitorio y sala de estar |
| `scripts/09_performance_indexes.sql` | Indices compuestos `idx_habitaciones_usuario_creado` e `idx_muebles_habitacion_xz` |
| `scripts/10_analytical_views.sql` | Vistas `vw_resumen_espacios_por_usuario` y `vw_densidad_mobiliario` |
| `scripts/procedures/sp_maintenance.sql` | Funcion `fn_purgar_habitaciones_vacias` |
| `scripts/11_supabase_policies.sql` | Columna `usuarios.auth_id` y politicas RLS de `habitaciones` y `muebles_sugeridos` (solo Supabase) |
| `docs/architecture_data.md` | Indices, planes de ejecucion medidos y troubleshooting de extensiones |
| `docs/performance_tuning.md` | Planes `EXPLAIN ANALYZE` de los indices compuestos y de las politicas RLS |
| `scripts/qa_tests/` | Suite de pruebas SQL (8 pruebas y el orquestador `run_qa_suite.sql`) |
| `docs/qa_strategy.md` | Convenciones de las pruebas, matrices de cobertura y flujo de una lectura con RLS |
| `scripts/12_db_maintenance.sql` | Procedimiento `sp_ejecutar_vacuum_analitico` y funcion `fn_reindexar_tablas_espaciales` |
| `scripts/13_partitioning.sql` | Convierte `historial_ia` en tabla particionada por rango de `creado_en` |
| `scripts/procedures/sp_backups.sql` | Tabla `log_respaldos` y funciones `fn_generar_backup_json_habitacion` y `fn_registrar_respaldo` |
| `docs/maintenance_guide.md` | Ventanas de mantenimiento, monitoreo del almacenamiento en Supabase y diagrama de las rutinas |
| `scripts/14_spatial_collisions.sql` | Funcion `fn_verificar_colision_mueble` y trigger `trg_impedir_superposicion` |
| `scripts/procedures/sp_vector_math.sql` | Funcion `fn_calcular_centro_masa_habitacion` |
| `scripts/15_stress_seeds.sql` | Hotel de 20 habitaciones y 50 muebles para pruebas de carga |
| `scripts/16_cron_jobs.sql` | Funcion `fn_purgar_logs_auditoria` y su tarea de pg_cron |
| `docs/spatial_math_guide.md` | Algebra vectorial, colisiones por radio, integracion con el Octree y diagramas del modelo espacial |

## Diagrama entidad-relacion

```
+--------------------------+          +------------------------------+
|       habitaciones       |          |      muebles_sugeridos       |
+--------------------------+          +------------------------------+
| PK id           SERIAL   |1        N| PK id            SERIAL      |
|    nombre       VARCHAR  |----------| FK habitacion_id INTEGER     |
|    alto         FLOAT    |          |    nombre        VARCHAR     |
|    ancho        FLOAT    |          |    posicion_x    FLOAT       |
|    profundidad  FLOAT    |          |    posicion_y    FLOAT       |
|    creado_en    TIMESTAMPTZ         |    posicion_z    FLOAT       |
+--------------------------+          |    ancho         FLOAT       |
             |1                       |    alto          FLOAT       |
             |                        |    profundidad   FLOAT       |
             |                        |    creado_en     TIMESTAMPTZ |
             |                        +------------------------------+
             |N
+--------------------------+
|       historial_ia       |
+--------------------------+
| PK id           SERIAL   |
| FK habitacion_id INTEGER |
|    recomendacion TEXT    |
|    creado_en    TIMESTAMPTZ
+--------------------------+
```

- Una habitacion tiene **muchos** muebles; cada mueble pertenece a **una sola** habitacion
  (`fk_muebles_habitacion`). Las coordenadas son metros relativos a la esquina origen de la habitacion.
- Una habitacion tiene **muchas** recomendaciones de OmniRoute en `historial_ia`.
- Ambas llaves foraneas usan `ON DELETE CASCADE`: al borrar una habitacion se borran sus muebles e historial.

## Modelo de seguridad y roles

```
+---------------------------+       +-----------------------------+       +------------------------+
|         usuarios          |       |        usuario_roles        |       |         roles          |
+---------------------------+       +-----------------------------+       +------------------------+
| PK id            SERIAL   |1     N| PK,FK usuario_id INTEGER    |N     1| PK id         SERIAL   |
|    nombre_usuario VARCHAR |-------| PK,FK rol_id     INTEGER    |-------|    nombre     VARCHAR  |
|    email         VARCHAR  |       |    asignado_en TIMESTAMPTZ  |       |    descripcion TEXT    |
|    password_hash TEXT     |       +-----------------------------+       +------------------------+
|    activo        BOOLEAN  |
|    creado_en     TIMESTAMPTZ
+---------------------------+
      |1                |1
      |N                |N
+--------------+   +---------------------------+
| habitaciones |   |         sesiones          |
| FK usuario_id|   | FK usuario_id  INTEGER    |
+--------------+   |    token_hash  CHAR(64)   |
                   |    expira_en   TIMESTAMPTZ|
                   |    revocada    BOOLEAN    |
                   +---------------------------+
```

- **Contrasenas:** `password_hash` guarda una firma bcrypt generada con `crypt(clave, gen_salt('bf'))` de
  `pgcrypto`. Para validar un login: `password_hash = crypt(clave_ingresada, password_hash)`.
- **Roles:** `roles` se carga con `estudiante` y `administrador`. `usuario_roles` es la tabla puente
  muchos a muchos; su llave primaria compuesta evita asignar dos veces el mismo rol.
- **Dueno de cada habitacion:** `04_security.sql` agrega `habitaciones.usuario_id` como llave foranea
  `NOT NULL`. Las habitaciones que ya existian se asignan a la cuenta `sistema`, que esta inactiva y cuyo
  hash es la firma bcrypt de un secreto aleatorio descartado, por lo que no puede iniciar sesion.
- **Sesiones:** el navegador recibe un token; la base solo guarda su SHA-256 (`token_hash`).
  `fn_validar_sesion(token)` devuelve el `usuario_id` si la sesion no esta expirada ni revocada y la cuenta
  esta activa, o `NULL` en caso contrario.

Ejecucion de los scripts nuevos, en este orden y despues de `03_seed.sql`:

```bash
psql -d modelado_3d -f scripts/04_security.sql
psql -d modelado_3d -f scripts/05_audit_logs.sql
psql -d modelado_3d -f scripts/procedures/sp_security.sql
psql -d modelado_3d -f scripts/procedures/sp_triggers.sql
psql -d modelado_3d -f scripts/06_advanced_queries.sql
```

`CREATE EXTENSION pgcrypto` requiere un usuario con permiso para crear extensiones (por ejemplo `postgres`).

## Auditoria de posiciones 3D (triggers)

Cada vez que cambian las coordenadas de un mueble (por ejemplo cuando la IA de OmniRoute lo reubica), la
base guarda la posicion anterior y la nueva sin que la aplicacion tenga que hacer nada extra.

| Pieza | Archivo | Funcion |
|---|---|---|
| `auditoria_muebles` | `05_audit_logs.sql` | Una fila por movimiento: `old_x/old_y/old_z`, `new_x/new_y/new_z`, `modificado_por`, `modificado_en` |
| `fn_log_mueble_movement()` | `procedures/sp_triggers.sql` | Compara `ROW(OLD.posicion_*)` con `ROW(NEW.posicion_*)` usando `IS NOT DISTINCT FROM`; si son iguales no hace nada, si difieren inserta en `auditoria_muebles` |
| `trg_audit_muebles_cambios` | `procedures/sp_triggers.sql` | `AFTER UPDATE OF posicion_x, posicion_y, posicion_z ON muebles_sugeridos FOR EACH ROW` |

Comportamiento:

- **Solo coordenadas.** `UPDATE OF` hace que renombrar un mueble no dispare el trigger, y la comparacion
  interna descarta los `UPDATE` que reescriben el mismo valor (`SET posicion_x = posicion_x`).
- **AFTER, no BEFORE.** El registro se escribe cuando el cambio ya paso todas las restricciones. Como
  corre dentro de la misma transaccion, si el `UPDATE` hace `ROLLBACK` tambien se descarta la auditoria.
- **Quien lo movio.** El backend debe ejecutar `SET LOCAL app.usuario_id = '<id>'` al inicio de cada
  transaccion; el trigger lo lee con `current_setting('app.usuario_id', true)`. Si no esta definido (un
  `UPDATE` manual en `psql`), `modificado_por` queda en `NULL`.
- **Borrado.** `auditoria_muebles.mueble_id` usa `ON DELETE CASCADE`: al eliminar un mueble se elimina su
  historial, igual que el resto del esquema.

Prueba rapida:

```sql
BEGIN;
SET LOCAL app.usuario_id = '1';
UPDATE muebles_sugeridos SET posicion_x = 2.5 WHERE nombre = 'Sofa';
COMMIT;

SELECT mueble_id, old_x, new_x, modificado_por FROM auditoria_muebles;
-- espera 1 fila: old_x = 2.0, new_x = 2.5, modificado_por = 1
```

## Flujo de autenticacion y persistencia

Secuencia desde el inicio de sesion hasta que una coordenada queda auditada:

```
 Navegador              API Python                         PostgreSQL (modelado_3d)
    |                       |                                         |
    | POST /login           |                                         |
    | (usuario, clave)      |                                         |
    |---------------------->| SELECT id FROM usuarios                 |
    |                       |  WHERE password_hash = crypt(clave, ...)|
    |                       |---------------------------------------->|
    |                       |<----------------------------------------| id
    |                       | INSERT INTO sesiones (sha256(token))    |
    |                       | INSERT INTO logs_actividad ('login')    |
    |                       |---------------------------------------->|
    |<----------------------| token                                   |
    |                       |                                         |
    | PUT /muebles/:id      |                                         |
    | Authorization: token  |                                         |
    |---------------------->| SELECT fn_validar_sesion(token)         |
    |                       |---------------------------------------->|
    |                       |<----------------------------------------| usuario_id (o NULL -> 401)
    |                       | BEGIN                                   |
    |                       | SET LOCAL app.usuario_id = usuario_id   |
    |                       | UPDATE muebles_sugeridos SET posicion_* |
    |                       |---------------------------------------->|
    |                       |                                         |--+ trg_audit_muebles_cambios
    |                       |                                         |  | fn_log_mueble_movement()
    |                       |                                         |<-+ INSERT auditoria_muebles
    |                       | INSERT INTO logs_actividad              |      (old_*, new_*)
    |                       |   ('peticion_api')                      |
    |                       | COMMIT                                  |
    |                       |---------------------------------------->|
    |<----------------------| 200 OK                                  |
```

El `UPDATE`, el registro del trigger y la entrada de `logs_actividad` van en la misma transaccion: o se
guardan los tres o ninguno.

## Despliegue y ejecucion de los scripts

Requisitos: PostgreSQL 14+ con el cliente `psql` en el `PATH`. El servidor escucha por defecto en el
puerto **5432**; si tu instalacion usa otro (por ejemplo 5433 cuando hay dos versiones instaladas),
cambia `-p` en los comandos o define la variable `PGPORT`.

```bash
# Conexion (ajusta a tu instalacion)
export PGHOST=localhost
export PGPORT=5432
export PGUSER=postgres

# 1) Crear la base y las tablas. Se ejecuta contra la base "postgres",
#    porque 01_schema.sql crea modelado_3d y luego se conecta con \c.
psql -d postgres -f scripts/01_schema.sql

# 2) Indices y 3) datos semilla, directamente sobre modelado_3d
psql -d modelado_3d -f scripts/02_indexes.sql
psql -d modelado_3d -f scripts/03_seed.sql
```

En PowerShell usa `$env:PGPORT = "5432"` en lugar de `export`.

Comprobacion rapida (espera 1 habitacion y 2 muebles):

```sql
SELECT h.nombre, m.nombre, m.posicion_x, m.posicion_y, m.posicion_z
FROM habitaciones h JOIN muebles_sugeridos m ON m.habitacion_id = h.id;
```

Para empezar de cero: `psql -d postgres -c "DROP DATABASE IF EXISTS modelado_3d;"`.

> Estos scripts son para PostgreSQL local. `CREATE DATABASE` y `\c` no funcionan en el SQL Editor de
> Supabase; para Supabase usa `schema.sql` como se describe arriba.

## Motor analitico SQL

Convencion de ejes, igual a la de Three.js: **X** es el ancho, **Y** la altura desde el piso y **Z** la
profundidad, en metros desde la esquina origen de la habitacion. La posicion de un mueble es el centro de
su base.

### Distancia euclidiana (`fn_distancia_euclidiana`)

Para dos puntos P1 = (x1, y1, z1) y P2 = (x2, y2, z2):

```
d(P1, P2) = sqrt( (x2 - x1)^2 + (y2 - y1)^2 + (z2 - z1)^2 )
```

Es el teorema de Pitagoras aplicado dos veces: primero la diagonal en el piso, sqrt(dx^2 + dz^2), y luego
la hipotenusa entre esa diagonal y la diferencia de altura dy. La funcion es `IMMUTABLE` y `STRICT`: solo
depende de sus argumentos y devuelve `NULL` si alguno es `NULL`.

```sql
-- Sofa y mesa de centro de la sala de estar: (2.5, 0, 0.45) y (2.5, 0, 2.0)
SELECT fn_distancia_euclidiana(2.5, 0, 0.45, 2.5, 0, 2.0);   -- 1.55
```

### Validacion de limites (`trg_muebles_limites_check`)

Un mueble de medidas (a, h, p) en la posicion (x, y, z) dentro de una habitacion de medidas
(ancho, alto, profundidad) es valido solo si su caja envolvente cabe en la de la habitacion:

```
0 <= x - a/2      y   x + a/2 <= ancho
0 <= y            y   y + h   <= alto
0 <= z - p/2      y   z + p/2 <= profundidad
```

- `fn_check_boundaries()` evalua las tres desigualdades y, si alguna falla, aborta con
  `check_violation` (SQLSTATE `23514`) indicando el eje y el intervalo ocupado.
- El trigger es `BEFORE INSERT OR UPDATE OF habitacion_id, posicion_*, ancho, alto, profundidad`: la fila
  invalida nunca llega a escribirse, y como corre antes que `trg_audit_muebles_cambios` (AFTER), un
  movimiento rechazado tampoco queda en la auditoria.
- Las medidas son opcionales; si faltan, el mueble se valida como un punto (a = h = p = 0).
- Se admite un margen de 1e-9 m para el redondeo de `FLOAT`, asi un mueble pegado a la pared no se rechaza.

```sql
INSERT INTO muebles_sugeridos (habitacion_id, nombre, posicion_x, posicion_y, posicion_z)
VALUES (1, 'Lampara', 4.5, 0, 1);
-- ERROR:  Mueble "Lampara" fuera de la habitacion 1 en el eje X
-- DETAIL: Ocupa [4.5, 4.5] y el ancho permitido es [0, 4].
```

### Ocupacion volumetrica

```
V_habitacion = alto * ancho * profundidad                    -- fn_calcular_volumen_util(id)
V_muebles    = suma de (ancho * alto * profundidad) por mueble -- fn_calcular_volumen_mobiliario(id)
ocupacion    = 100 * V_muebles / V_habitacion
```

`V_muebles` usa la caja envolvente de cada mueble, por lo que sobreestima la ocupacion de formas
irregulares; los muebles sin medidas aportan 0.

```sql
SELECT h.nombre,
       round((100 * fn_calcular_volumen_mobiliario(h.id)
                  / fn_calcular_volumen_util(h.id))::NUMERIC, 2) AS ocupacion_pct
FROM habitaciones h;
```

Ejecucion, despues de `06_advanced_queries.sql`:

```bash
psql -d modelado_3d -f scripts/07_spatial_constraints.sql
psql -d modelado_3d -f scripts/procedures/sp_room_analytics.sql
psql -d modelado_3d -f scripts/08_extended_seeds.sql
```

## Rendimiento, vistas y seguridad RLS en Supabase

### Indices compuestos (`09_performance_indexes.sql`)

| Indice | Columnas | Consulta que acelera |
|---|---|---|
| `idx_habitaciones_usuario_creado` | `(usuario_id, creado_en DESC)` | Habitaciones de una cuenta, de la mas reciente a la mas antigua, y el filtro de la politica RLS |
| `idx_muebles_habitacion_xz` | `(habitacion_id, posicion_x, posicion_z)` | Muebles de una habitacion dentro de una franja X-Z, antes del raycasting del Canvas 3D |

Ambos reemplazan a los indices de una sola columna `idx_habitaciones_usuario` e `idx_muebles_habitacion`,
que son su prefijo, y el script los elimina. Con 100 000 muebles, la consulta de la franja paso de leer 50
filas y 52 paginas a leer 1 fila y 4 paginas. El detalle esta en `docs/performance_tuning.md`.

### Vistas analiticas (`10_analytical_views.sql`)

| Vista | Columnas |
|---|---|
| `vw_resumen_espacios_por_usuario` | `usuario_id`, `nombre_usuario`, `total_habitaciones`, `ultima_habitacion_en` |
| `vw_densidad_mobiliario` | `habitacion_id`, `usuario_id`, `nombre`, `area_util_m2`, `total_muebles`, `muebles_por_m2`, `huella_piso_pct` |

```
area_util_m2    = ancho * profundidad                      (planta X-Z de la habitacion)
muebles_por_m2  = total_muebles / area_util_m2
huella_piso_pct = 100 * suma(ancho * profundidad del mueble) / area_util_m2
```

Las dos usan `security_invoker = true` (PostgreSQL 15+): se evaluan con los permisos de quien consulta, asi
que las politicas RLS tambien filtran los reportes y cada usuario solo ve sus propias filas.

### Limpieza de habitaciones vacias (`procedures/sp_maintenance.sql`)

`fn_purgar_habitaciones_vacias(p_antiguedad INTERVAL DEFAULT '7 days')` borra las habitaciones sin muebles
creadas hace mas de `p_antiguedad` y devuelve cuantas borro. El margen protege las habitaciones que el
usuario acaba de crear. El permiso `EXECUTE` se revoca a `PUBLIC`, `anon` y `authenticated`: solo el dueno
de las tablas puede llamarla, y no queda expuesta como RPC en la API de Supabase.

```sql
SELECT fn_purgar_habitaciones_vacias();                    -- margen de 7 dias
SELECT fn_purgar_habitaciones_vacias(INTERVAL '1 day');

-- Programada con pg_cron, todos los dias a las 03:00 UTC
SELECT cron.schedule('purgar-habitaciones-vacias', '0 3 * * *',
                     $$SELECT fn_purgar_habitaciones_vacias()$$);
```

### Politicas RLS (`11_supabase_policies.sql`)

Este script es el unico de `scripts/` que necesita Supabase: usa `auth.users` y `auth.uid()`. Se aplica
cuando el esquema de `scripts/` se despliega en un proyecto de Supabase y el frontend lee las tablas
directamente por la API REST con el JWT del usuario.

| Pieza | Efecto |
|---|---|
| `usuarios.auth_id UUID` | Enlaza la cuenta local (`usuarios.id`, `INTEGER`) con la de Supabase Auth (`auth.uid()`, `UUID`) |
| `ENABLE ROW LEVEL SECURITY` en `habitaciones` y `muebles_sugeridos` | Sin politica, `anon` y `authenticated` no ven ninguna fila |
| `pol_habitaciones_select_propias` | `authenticated` lee solo las habitaciones cuyo `usuario_id` es el de su `auth_id` |
| `pol_muebles_select_propios` | `authenticated` lee solo los muebles de esas habitaciones |

- Solo hay politicas `SELECT`: por la API nadie puede insertar, modificar ni borrar. Las escrituras pasan
  por el backend, que se conecta como dueno de las tablas y no es filtrado por RLS.
- `anon` no tiene politica: una peticion sin sesion recibe 0 filas, no un error.
- Una cuenta con `auth_id` en `NULL` (por ejemplo `sistema`) no ve nada por la API.
- `auth.uid()` va envuelta en `(SELECT ...)` y la lista de habitaciones en `ARRAY(...)` para que PostgreSQL
  las calcule una vez por consulta y use los indices; con `IN (...)` el conteo de muebles recorria la
  tabla completa (28 ms contra 2 ms con 100 000 filas).

Enlazar una cuenta y comprobar el aislamiento desde el SQL Editor:

```sql
UPDATE usuarios SET auth_id = '<uuid de Authentication -> Users>' WHERE nombre_usuario = '<usuario>';

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "<uuid>", "role": "authenticated"}', true);
SELECT * FROM vw_resumen_espacios_por_usuario;   -- espera solo la fila de ese usuario
ROLLBACK;
```

Ejecucion, despues de `08_extended_seeds.sql`. Los tres primeros funcionan tambien en PostgreSQL local:

```bash
psql -d modelado_3d -f scripts/09_performance_indexes.sql
psql -d modelado_3d -f scripts/10_analytical_views.sql
psql -d modelado_3d -f scripts/procedures/sp_maintenance.sql
psql -d modelado_3d -f scripts/11_supabase_policies.sql      # solo en Supabase
```

## Suite de QA (`scripts/qa_tests/`)

Pruebas automatizadas de las reglas que viven en la base: llaves foraneas, triggers, funciones, indices y
politicas RLS. Cada prueba crea sus propios datos (prefijo `QA`) dentro de una transaccion que termina en
`ROLLBACK`, asi que se puede correr sobre una base con datos reales sin modificarlos. Requiere que la base ya
tenga aplicados todos los scripts anteriores.

| Prueba | Verifica | Donde corre |
|---|---|---|
| `test_funcion_distancia_euclidiana.sql` | d((1,1,1), (4,5,1)) = 5 y propiedades de `fn_distancia_euclidiana` | Local y Supabase |
| `test_insert_coordenadas_validas.sql` | Insercion de un mueble en el origen (0, 0, 0) | Local y Supabase |
| `test_error_usuario_inexistente.sql` | Rechazo por llave foranea de usuarios y habitaciones inexistentes | Local y Supabase |
| `test_limite_volumen_maximo.sql` | Trigger de limites en una nave de 120 x 15 x 80 m | Local y Supabase |
| `test_movimiento_coordenada_old_new.sql` | Auditoria `old_*`/`new_*` al mover un mueble | Local y Supabase |
| `test_limpieza_espacios_vicios.sql` | `fn_purgar_habitaciones_vacias` y su `historial_ia` | Local y Supabase |
| `test_indice_performance_query.sql` | `EXPLAIN` usa los indices B-Tree compuestos | Local y Supabase |
| `test_rls_security_auth.sql` | `anon` y un JWT sin cuenta no leen ni escriben filas | Solo Supabase |

### Desde la consola de Supabase (SQL Editor)

1. Abre **SQL Editor -> New query**.
2. Pega el contenido completo de una prueba, por ejemplo `scripts/qa_tests/test_rls_security_auth.sql`, y
   pulsa **Run**. Pega siempre el archivo completo: el `ROLLBACK` final es el que descarta los datos de
   prueba (en `test_limpieza_espacios_vicios.sql` tambien deshace la purga de las habitaciones reales).
3. Revisa la salida: cada caso superado imprime `OK ...` y la prueba termina con
   `OK <nombre>: todas las aserciones superadas`. Si algo falla, el editor muestra el error del `ASSERT`
   con el valor esperado y el obtenido, por ejemplo `ERROR: anon ve 3 habitaciones; se esperaban 0`.
4. Repite con las demas pruebas. El orden no importa.

`run_qa_suite.sql` no funciona en el SQL Editor porque usa meta-comandos de `psql` (`\ir`, `\if`).

### Con `psql` (local o contra Supabase)

El orquestador corre las 8 pruebas en orden y se detiene en la primera que falla. Detecta si la base es
Supabase (existe el esquema `auth`) y, si no lo es, omite la prueba RLS.

```bash
# PostgreSQL local
psql -d modelado_3d -f scripts/qa_tests/run_qa_suite.sql

# Supabase: la cadena del Session pooler (ver la seccion de Supabase al inicio)
psql "postgres://postgres.<project-ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres" \
     -f scripts/qa_tests/run_qa_suite.sql
```

Termina con `== Suite de QA completada sin fallos ==`. Si una prueba falla, `psql` sale con codigo 3, lo que
permite usar el orquestador en un pipeline de CI. Las convenciones de las pruebas, las matrices de cobertura y
la forma en que se valido la suite estan en `docs/qa_strategy.md`.

## Mantenimiento automatizado (pg_cron y PL/pgSQL)

Rutinas para mantener compactas las tablas que mas cambian, partir el historial de la IA por fechas y
respaldar habitaciones individuales. Todas se ejecutan como dueno de las tablas: `EXECUTE` esta revocado a
`PUBLIC`, `anon` y `authenticated`, asi que ninguna queda publicada como RPC en la API de Supabase.

| Pieza | Archivo | Que hace |
|---|---|---|
| `sp_ejecutar_vacuum_analitico(umbral DEFAULT 0.10)` | `12_db_maintenance.sql` | `ANALYZE` de `muebles_sugeridos` y `NOTICE` si las tuplas muertas superan el umbral |
| `fn_reindexar_tablas_espaciales()` | `12_db_maintenance.sql` | `REINDEX` de `idx_muebles_habitacion_xz`, `idx_habitaciones_usuario_creado` e `idx_auditoria_muebles_mueble`; devuelve el tamano antes y despues |
| `historial_ia` particionada | `13_partitioning.sql` | `PARTITION BY RANGE (creado_en)` con `historial_ia_2026` (periodo actual) e `historial_ia_default` (anos anteriores); llave primaria `(id, creado_en)` |
| `log_respaldos` | `procedures/sp_backups.sql` | Una fila por respaldo: habitacion, numero de muebles, tamano, `checksum_md5`, quien y cuando |
| `fn_generar_backup_json_habitacion(id)` | `procedures/sp_backups.sql` | Devuelve la habitacion y sus muebles como texto JSON y la registra en `log_respaldos` con `fn_registrar_respaldo` |

- **`VACUUM` va fuera del procedimiento.** PostgreSQL no permite `VACUUM` dentro de una funcion, un
  procedimiento ni una transaccion. Se programa como sentencia suelta en pg_cron, que ejecuta cada tarea por
  separado; el procedimiento refresca estadisticas y confirma el resultado.
- **`REINDEX` bloquea.** Mientras corre, `fn_reindexar_tablas_espaciales()` bloquea las escrituras sobre las
  tres tablas; por eso se programa semanalmente en la ventana de menor uso.
- **Particiones.** Una consulta con rango de fechas dentro de 2026 lee solo `historial_ia_2026`. Cada diciembre
  se crea la particion del ano siguiente; un ano viejo se retira con `DETACH PARTITION` sin `DELETE` masivo.
- **Respaldos.** La exportacion es un solo `SELECT`: no bloquea a otros usuarios y ve una foto consistente. El
  registro en `log_respaldos` va en la misma transaccion, asi que solo existe si la exportacion termino bien.

Tareas programadas con pg_cron (hora UTC; la ventana de 08:00 a 10:00 UTC es de 03:00 a 05:00 en Colombia):

| Tarea | Cron | Comando |
|---|---|---|
| `purgar-habitaciones-vacias` | `0 3 * * *` | `SELECT fn_purgar_habitaciones_vacias()` |
| `purgar-logs-auditoria` | `15 8 * * *` | `SELECT * FROM fn_purgar_logs_auditoria(30)` (`16_cron_jobs.sql`, ver abajo) |
| `vacuum-muebles` | `30 8 * * *` | `VACUUM (ANALYZE) muebles_sugeridos` |
| `diagnostico-muebles` | `45 8 * * *` | `CALL sp_ejecutar_vacuum_analitico()` |
| `reindexar-espaciales` | `0 9 * * 0` | `SELECT * FROM fn_reindexar_tablas_espaciales()` |

```sql
-- Respaldo manual de la habitacion 1 y su registro
SELECT fn_generar_backup_json_habitacion(1);
SELECT habitacion_id, total_muebles, tamano_bytes, checksum_md5, ejecutado_en
FROM log_respaldos ORDER BY ejecutado_en DESC;

-- En que particion quedo cada recomendacion
SELECT tableoid::REGCLASS AS particion, id, creado_en FROM historial_ia ORDER BY creado_en;
```

Ejecucion, despues de `11_supabase_policies.sql` (o de `procedures/sp_maintenance.sql` en PostgreSQL local).
`13_partitioning.sql` se ejecuta una sola vez: renombra la tabla actual, copia sus filas a la particionada y la
borra, todo en una transaccion.

```bash
psql -d modelado_3d -f scripts/12_db_maintenance.sql
psql -d modelado_3d -f scripts/13_partitioning.sql
psql -d modelado_3d -f scripts/procedures/sp_backups.sql
```

Las ventanas de tiempo, las consultas para vigilar el tamano de la base en Supabase y el diagrama de como
estas rutinas mantienen las paginas calientes en memoria estan en `docs/maintenance_guide.md`.

## Motor vectorial y control de colisiones

La base de datos rechaza muebles superpuestos y calcula el centro de masa del mobiliario de cada habitacion con
algebra vectorial en PL/pgSQL. La matematica, la integracion con el Octree del backend y los diagramas del
modelo espacial estan en `docs/spatial_math_guide.md`.

| Pieza | Archivo | Que hace |
|---|---|---|
| `fn_verificar_colision_mueble(hab, x, y, z, radio DEFAULT 0.10, excluir_id DEFAULT NULL)` | `14_spatial_collisions.sql` | Devuelve el id del mueble mas cercano a menos de `radio` metros del punto, o `NULL` si el espacio esta libre |
| `trg_impedir_superposicion` | `14_spatial_collisions.sql` | `BEFORE INSERT ON muebles_sugeridos`: rechaza con `exclusion_violation` (23P01) un mueble a menos de 0.10 m de otro de su habitacion |
| `fn_calcular_centro_masa_habitacion(hab)` | `procedures/sp_vector_math.sql` | `(avg(x), avg(y), avg(z))` de los muebles y cuantos son |
| Hotel de estres | `15_stress_seeds.sql` | `Hotel Estres - Habitacion 01` a `20` con 50 muebles sobre la diagonal de cada planta |
| `fn_purgar_logs_auditoria(dias DEFAULT 30)` | `16_cron_jobs.sql` | Borra de `logs_actividad` y `auditoria_muebles` lo que tenga mas de `dias` dias; se programa a diario si existe pg_cron |

- **Colision = distancia entre posiciones menor que el radio.** Se compara el centro de la base de cada mueble,
  no sus cajas: separar las cajas completas es trabajo del Octree. La base solo es la ultima barrera contra
  duplicados (dobles clics, reintentos, `INSERT` manuales).
- **Concurrencia.** Cada insercion toma `pg_advisory_xact_lock(14, habitacion_id)`: dos inserciones en la misma
  habitacion se validan de una en una y no pueden aprobarse mutuamente.
- **Orden de los triggers.** PostgreSQL los ejecuta en orden alfabetico, asi que `trg_impedir_superposicion`
  corre antes que `trg_muebles_limites_check`.
- **Solo `INSERT`.** Mover un mueble con `UPDATE` y los muebles que ya existian no se revisan. La
  "Mesa de centro" y la "Alfombra" de `08_extended_seeds.sql` comparten posicion y fallarian si ese script se
  ejecutara despues de `14_spatial_collisions.sql`.

Ejecucion, despues de `procedures/sp_backups.sql`:

```bash
psql -d modelado_3d -f scripts/14_spatial_collisions.sql
psql -d modelado_3d -f scripts/procedures/sp_vector_math.sql
psql -d modelado_3d -f scripts/15_stress_seeds.sql
psql -d modelado_3d -f scripts/16_cron_jobs.sql
```

`15_stress_seeds.sql` y `16_cron_jobs.sql` se pueden volver a ejecutar: el hotel no se duplica y la tarea de
pg_cron se reemplaza. Sin pg_cron, `16_cron_jobs.sql` solo crea la funcion y avisa con un `NOTICE`.

### Pruebalo en el SQL Editor

<details>
<summary>Insertar un mueble duplicado y ver como se rechaza</summary>

```sql
BEGIN;

-- La "Silla 01-1" del hotel esta en (1.25, 0, 1.25). Un mueble a 5 cm choca.
INSERT INTO muebles_sugeridos (habitacion_id, nombre, posicion_x, posicion_y, posicion_z)
SELECT habitacion_id, 'Silla duplicada', posicion_x + 0.05, posicion_y, posicion_z
FROM muebles_sugeridos WHERE nombre = 'Silla 01-1';
-- ERROR:  Mueble "Silla duplicada" superpuesto con "Silla 01-1" (id ...) en la habitacion ...
-- DETAIL: (1.3, 0, 1.25) esta a 0.0500 m de (1.25, 0, 1.25); el minimo es 0.1 m.

ROLLBACK;
```

</details>

<details>
<summary>Preguntar si un punto esta libre antes de insertar</summary>

```sql
SELECT h.nombre,
       fn_verificar_colision_mueble(h.id, 1.25, 0, 1.25)  AS choca_con,      -- id de la silla
       fn_verificar_colision_mueble(h.id, 1.40, 0, 1.25)  AS a_15_cm,        -- NULL: libre
       fn_verificar_colision_mueble(h.id, 1.25, 0, 1.25, 0.10,
         (SELECT id FROM muebles_sugeridos WHERE nombre = 'Silla 01-1')) AS sin_ella  -- NULL
FROM habitaciones h
WHERE h.nombre = 'Hotel Estres - Habitacion 01';
```

</details>

<details>
<summary>Centro de masa de cada habitacion y desvio respecto al centro de la planta</summary>

```sql
SELECT h.nombre, c.total_muebles,
       round(c.centro_x::NUMERIC, 3) AS cx,
       round(c.centro_z::NUMERIC, 3) AS cz,
       round(fn_distancia_euclidiana(c.centro_x, 0, c.centro_z,
                                     h.ancho / 2, 0, h.profundidad / 2)::NUMERIC, 3) AS desvio_m
FROM habitaciones h
CROSS JOIN LATERAL fn_calcular_centro_masa_habitacion(h.id) c
ORDER BY h.id;
```

En la `Hotel Estres - Habitacion 01` (5 x 5 m, tres muebles en la diagonal) el centro de masa es
`(2.5, 0, 2.5)`, el centro exacto de la planta: `desvio_m = 0`.

</details>

<details>
<summary>Purgar a mano la auditoria antigua</summary>

```sql
SELECT * FROM fn_purgar_logs_auditoria(30);
--        tabla       | filas_borradas
-- -------------------+----------------
--  logs_actividad    |            ...
--  auditoria_muebles |            ...
```

</details>
