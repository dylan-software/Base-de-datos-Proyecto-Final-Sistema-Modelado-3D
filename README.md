# Database — Supabase

This is NOT an application and has no repository of its own. It is one SQL file you run once.

## Files
- `schema.sql` — enables the `postgis` and `vector` extensions and creates the tables
  (`furniture`, `projects`, `spaces`, `placed_items`), their indexes, and turns on Row Level Security.
- `verify.sql` — queries that confirm the schema was applied correctly.

## Steps
1. Create a project at https://supabase.com. Choose a region and set a database password — **save it**, you need it in step 4.
2. Open **SQL Editor → New query**, paste the full contents of `schema.sql`, and click **Run**.
   It should finish with "Success. No rows returned".
   If `CREATE EXTENSION` is rejected, enable `postgis` and `vector` from **Database → Extensions** and run the script again.
3. New query → paste `verify.sql` → Run each query and compare with the "expect" comments inside the file.
4. Click **Connect** (top of the dashboard) and copy the **Session pooler** connection string. It looks like:
   `postgres://postgres.<project-ref>:[YOUR-PASSWORD]@aws-0-<region>.pooler.supabase.com:5432/postgres`
   Replace `[YOUR-PASSWORD]` with your password. If the password contains special characters (`@ : / # ?`),
   URL-encode them. This full string is what you set as `DATABASE_URL` in the **backend**.

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

Esquema relacional independiente del de Supabase para la aplicacion web de modelado 3D. Persiste las
dimensiones de las habitaciones, las coordenadas (X, Y, Z) de los muebles validados por el Octree y el
historial de recomendaciones esteticas que devuelve la API de OmniRoute.

| Archivo | Contenido |
|---|---|
| `scripts/01_schema.sql` | Crea la base `modelado_3d` y las tablas `habitaciones`, `muebles_sugeridos`, `historial_ia` |
| `scripts/02_indexes.sql` | Indice sobre la llave foranea `muebles_sugeridos.habitacion_id` |
| `scripts/03_seed.sql` | Habitacion vacia de 4x4 m con un sofa y un escritorio de prueba |

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
+--------------------------+          |    creado_en     TIMESTAMPTZ |
             |1                       +------------------------------+
             |
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
