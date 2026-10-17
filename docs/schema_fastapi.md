# FastAPI schema - entity-relationship diagram

The five tables of `schema.sql`, which mirror the backend's SQLAlchemy models (`app/models/*.py`). This is
the only document in `docs/` about the current schema; the others describe the obsolete `scripts/` schema.

```
+-------------------------------+
|           usuarios            |
+-------------------------------+
| PK id             SERIAL      |
|    nombre         VARCHAR(120)|
| UQ email          VARCHAR(254)|   ix_usuarios_email (unique)
|    password_hash  VARCHAR(255)|
+-------------------------------+
        :
        :  logical link, no foreign key:
        :  user_id = usuarios.id as text (the session token's "sub")
        :
        :.............................................
        :                                            :
+-------------------------------+     +-------------------------------+
|       muebles_catalogo        |     |         habitaciones          |
+-------------------------------+     +-------------------------------+
| PK id            SERIAL       |     | PK id           SERIAL        |
|    user_id       VARCHAR(64)  |     |    user_id      VARCHAR(64)   |
| FK categoria_id  INTEGER      |     |    nombre       VARCHAR(120)  |
|    nombre        VARCHAR(120) |     |    ancho        FLOAT  (m)    |
|    ancho         FLOAT  (cm)  |     |    alto         FLOAT  (m)    |
|    alto          FLOAT  (cm)  |     |    profundidad  FLOAT  (m)    |
|    profundidad   FLOAT  (cm)  |     |    vertices     JSONB  (m)    |
+-------------------------------+     +-------------------------------+
        | N                                    | 1
        |                                      |
        | 1                                    | N   ON DELETE CASCADE
+-------------------------------+     +-------------------------------+
|          categorias           |     |       muebles_sugeridos       |
+-------------------------------+     +-------------------------------+
| PK id      SERIAL             |     | PK id             SERIAL      |
| UQ nombre  VARCHAR(60)        |     | FK habitacion_id  INTEGER     |
+-------------------------------+     |    nombre         VARCHAR(120)|
  uq_categorias_nombre_lower          |    ancho          FLOAT  (m)  |
  (unique on lower(nombre))           |    alto           FLOAT  (m)  |
                                      |    profundidad    FLOAT  (m)  |
                                      |    posicion_x     FLOAT  (m)  |
                                      |    posicion_y     FLOAT  (m)  |
                                      |    posicion_z     FLOAT  (m)  |
                                      +-------------------------------+
```

Every column is `NOT NULL` except `user_id` (both tables) and `vertices`.

## Relationships

| From | To | Kind | On delete |
|---|---|---|---|
| `muebles_catalogo.categoria_id` | `categorias.id` | foreign key, N:1 | not allowed while items use the category |
| `muebles_sugeridos.habitacion_id` | `habitaciones.id` | foreign key, N:1 | `CASCADE`: the room's furniture is deleted |
| `habitaciones.user_id` | `usuarios.id` | logical only (text vs integer) | nothing happens |
| `muebles_catalogo.user_id` | `usuarios.id` | logical only (text vs integer) | nothing happens |

- `user_id` holds the `sub` of the backend's session token, which is `usuarios.id` as text. It is not a
  foreign key: the backend checks ownership on every request instead. Rows created before the column
  existed have `NULL` and belong to nobody.
- `muebles_sugeridos` does not reference `muebles_catalogo`: a placed piece stores its own name and
  sizes, in meters.
- `categorias` are shared by every account.

## Indexes

| Index | Table | Columns | Unique |
|---|---|---|---|
| `ix_usuarios_email` | `usuarios` | `email` | yes |
| `uq_categorias_nombre_lower` | `categorias` | `lower(nombre)` | yes |
| `ix_muebles_catalogo_categoria_id` | `muebles_catalogo` | `categoria_id` | no |
| `ix_muebles_catalogo_user_id` | `muebles_catalogo` | `user_id` | no |
| `ix_habitaciones_user_id` | `habitaciones` | `user_id` | no |
| `ix_muebles_sugeridos_habitacion_id` | `muebles_sugeridos` | `habitacion_id` | no |

## Units and coordinates

Catalog sizes are in centimeters; rooms and placed furniture are in meters. The floor is the x/z plane and
y points up. `vertices` is `[{"x": m, "y": m}, ...]`, where the polygon's `y` is the 3D z axis, and
`NULL` means the rectangle `[0, ancho] x [0, profundidad]`. `posicion_x` / `posicion_z` are the center
of the footprint and `posicion_y` the height of the base. The root `README.md` has the details.

## Security

RLS is enabled on the five tables with no policies, so Supabase's REST API returns nothing for `anon` and
`authenticated`. The backend connects as the owner of the tables and is not affected.
