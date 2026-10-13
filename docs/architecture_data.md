# Arquitectura de persistencia

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
| `muebles_sugeridos.habitacion_id` | `idx_muebles_habitacion` |
| `habitaciones.usuario_id` | `idx_habitaciones_usuario` |
| `logs_actividad.usuario_id` | `idx_logs_actividad_usuario (usuario_id, creado_en)` |
| `auditoria_muebles.mueble_id` | `idx_auditoria_muebles_mueble (mueble_id, modificado_en)` |
| `usuario_roles.usuario_id` | Cubierto por la llave primaria `(usuario_id, rol_id)` |
| `historial_ia.habitacion_id` | **Ninguno** |
| `sesiones.usuario_id` | **Ninguno** |
| `usuario_roles.rol_id` | **Ninguno** (la tabla `roles` tiene 2 filas; no se justifica) |

Pendiente: `historial_ia.habitacion_id` es el caso medido arriba y conviene indexarlo si el panel de IA
consulta el historial por habitacion. `sesiones.usuario_id` solo se recorre al borrar un usuario, porque
`fn_validar_sesion` busca por `token_hash`, que ya es `UNIQUE`.
