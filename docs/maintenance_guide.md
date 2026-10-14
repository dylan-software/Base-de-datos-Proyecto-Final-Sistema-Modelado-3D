# Guia de mantenimiento y conservacion del almacenamiento

Este documento explica cuando y como correr las rutinas de `scripts/12_db_maintenance.sql`,
`scripts/13_partitioning.sql` y `scripts/procedures/sp_backups.sql`, y como vigilar el tamano de la base en
Supabase. Complementa a `fn_purgar_habitaciones_vacias` de `scripts/procedures/sp_maintenance.sql`.

## Rutinas disponibles

| Rutina | Script | Que hace | Bloquea |
|---|---|---|---|
| `VACUUM (ANALYZE) muebles_sugeridos` | Sentencia directa | Marca como reutilizable el espacio de las versiones viejas de cada fila y refresca las estadisticas | No |
| `CALL sp_ejecutar_vacuum_analitico(umbral)` | `12_db_maintenance.sql` | `ANALYZE` de `muebles_sugeridos` y aviso si las tuplas muertas superan el umbral (10 % por defecto) | No |
| `SELECT * FROM fn_reindexar_tablas_espaciales()` | `12_db_maintenance.sql` | `REINDEX` de los tres indices B-Tree que empiezan por una llave foranea; devuelve su tamano antes y despues | Escrituras en `muebles_sugeridos`, `habitaciones` y `auditoria_muebles` hasta que termina |
| `SELECT fn_purgar_habitaciones_vacias()` | `procedures/sp_maintenance.sql` | Borra habitaciones sin muebles con mas de 7 dias | Solo las filas borradas |
| `SELECT fn_generar_backup_json_habitacion(id)` | `procedures/sp_backups.sql` | Exporta una habitacion como texto JSON y la registra en `log_respaldos` | No |
| `CREATE TABLE historial_ia_<ano> PARTITION OF ...` | `13_partitioning.sql` | Crea la particion del ano siguiente | Brevemente `historial_ia` |

Todas se ejecutan como dueno de las tablas (`postgres` en Supabase): `EXECUTE` esta revocado a `anon` y
`authenticated`, y `VACUUM`, `ANALYZE` y `REINDEX` exigen ser dueno de la tabla.

**Por que `VACUUM` no esta dentro del procedimiento.** PostgreSQL no permite `VACUUM` dentro de una funcion o
procedimiento ("VACUUM cannot be executed from a function") ni dentro de `BEGIN ... COMMIT`. Se ejecuta como
sentencia suelta en el SQL Editor o como tarea de pg_cron, que corre cada comando por separado.

## Ventanas de tiempo

pg_cron usa la hora UTC. Colombia esta en UTC-5 todo el ano (no tiene horario de verano), asi que la ventana de
menor uso de la aplicacion, de 03:00 a 05:00 hora de Colombia, corresponde a **08:00 - 10:00 UTC**.

| Hora UTC | Hora Colombia | Frecuencia | Tarea |
|---|---|---|---|
| 03:00 | 22:00 | Diaria | `fn_purgar_habitaciones_vacias()` (ya programada en `sp_maintenance.sql`) |
| 08:30 | 03:30 | Diaria | `VACUUM (ANALYZE) muebles_sugeridos` |
| 08:45 | 03:45 | Diaria | `CALL sp_ejecutar_vacuum_analitico()`: confirma que el `VACUUM` dejo las tuplas muertas bajo el umbral |
| 09:00 | 04:00 | Semanal (domingo) | `fn_reindexar_tablas_espaciales()`: es la unica que bloquea, por eso va el dia de menos uso |
| A demanda | | Antes de que la IA reorganice una habitacion | `fn_generar_backup_json_habitacion(id)` |
| Diciembre | | Anual | Crear la particion `historial_ia_<ano siguiente>` |

Programacion (SQL Editor de Supabase, con `pg_cron` activado en **Database -> Extensions**):

```sql
SELECT cron.schedule('vacuum-muebles',       '30 8 * * *', $$VACUUM (ANALYZE) muebles_sugeridos$$);
SELECT cron.schedule('diagnostico-muebles',  '45 8 * * *', $$CALL sp_ejecutar_vacuum_analitico()$$);
SELECT cron.schedule('reindexar-espaciales', '0 9 * * 0',  $$SELECT * FROM fn_reindexar_tablas_espaciales()$$);

-- Resultado de las ultimas ejecuciones
SELECT jobid, command, status, return_message, start_time
FROM cron.job_run_details
ORDER BY start_time DESC
LIMIT 20;
```

Particion del ano siguiente, antes del 1 de enero. Si se olvida, las filas nuevas caen en
`historial_ia_default` y la aplicacion sigue funcionando, pero despues PostgreSQL no deja crear la particion
del ano mientras la default tenga filas de ese rango: hay que moverlas primero.

```sql
CREATE TABLE historial_ia_2027 PARTITION OF historial_ia
  FOR VALUES FROM ('2027-01-01 00:00:00+00') TO ('2028-01-01 00:00:00+00');
```

Para retirar un ano viejo sin `DELETE` masivo: `ALTER TABLE historial_ia DETACH PARTITION historial_ia_2026;`
y luego exportarla con `pg_dump -t historial_ia_2026` o borrarla con `DROP TABLE`.

## Monitoreo del almacenamiento en Supabase

### Desde el dashboard

- **Reports -> Database:** uso de disco, memoria y CPU del proyecto en el tiempo.
- **Usage** de la organizacion: tamano de la base frente al limite del plan. El plan
  gratuito permite 500 MB por proyecto; al pasarlo, Supabase puede poner la base en solo lectura.
- **Database -> Extensions:** activar `pg_cron` para las tareas programadas y `pgstattuple` para medir la
  fragmentacion de los indices.

### Tamano de la base y de cada tabla

```sql
-- Base completa
SELECT pg_size_pretty(pg_database_size(current_database()));

-- Tablas del esquema public: datos, indices y total (incluye TOAST)
SELECT c.relname                                       AS tabla,
       pg_size_pretty(pg_relation_size(c.oid))         AS datos,
       pg_size_pretty(pg_indexes_size(c.oid))          AS indices,
       pg_size_pretty(pg_total_relation_size(c.oid))   AS total
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
ORDER BY pg_total_relation_size(c.oid) DESC;

-- Particiones de historial_ia (la tabla padre no guarda filas: mide 0)
SELECT i.inhrelid::REGCLASS                                AS particion,
       pg_size_pretty(pg_total_relation_size(i.inhrelid))  AS total
FROM pg_inherits i
WHERE i.inhparent = 'historial_ia'::REGCLASS
ORDER BY 1;
```

### Tuplas muertas y ultimo mantenimiento

```sql
SELECT relname, n_live_tup, n_dead_tup,
       round(100.0 * n_dead_tup / GREATEST(n_live_tup + n_dead_tup, 1), 2) AS pct_muertas,
       last_vacuum, last_autovacuum, last_analyze, last_autoanalyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;
```

| Metrica | Valor sano | Que hacer si se pasa |
|---|---|---|
| `pct_muertas` de `muebles_sugeridos` | Menos de 10 % | `VACUUM (ANALYZE) muebles_sugeridos` |
| `last_autovacuum` / `last_vacuum` | Menos de unos dias en tablas con escrituras | Revisar que pg_cron este corriendo (`cron.job_run_details`) |
| Tamano total frente al plan | Menos de 80 % del limite | Purgar habitaciones vacias y retirar particiones viejas de `historial_ia` |

`VACUUM` normal no devuelve espacio al sistema operativo: deja las paginas libres para las proximas escrituras,
asi que la tabla deja de crecer pero no se encoge. Solo `VACUUM FULL` la encoge, y bloquea la tabla completa
mientras la reescribe; usarlo solo si la tabla quedo muy inflada y en la ventana de mantenimiento.

### Fragmentacion de los indices

Con `pgstattuple` activado:

```sql
SELECT 'idx_muebles_habitacion_xz' AS indice, avg_leaf_density, leaf_fragmentation
FROM pgstatindex('idx_muebles_habitacion_xz')
UNION ALL
SELECT 'idx_habitaciones_usuario_creado', avg_leaf_density, leaf_fragmentation
FROM pgstatindex('idx_habitaciones_usuario_creado');

-- Uso real de cada indice desde el ultimo reinicio de estadisticas
SELECT indexrelname, idx_scan, pg_size_pretty(pg_relation_size(indexrelid)) AS tamano
FROM pg_stat_user_indexes
ORDER BY idx_scan;
```

| Metrica | Recien creado | Reindexar cuando |
|---|---|---|
| `avg_leaf_density` | ~90 % (el `fillfactor` por defecto de un B-Tree) | Baja de 70 %: las hojas estan medio vacias y cada busqueda lee mas paginas |
| `leaf_fragmentation` | Cerca de 0 % | Supera 30 %: las hojas ya no estan en orden fisico |
| `bytes_despues` de `fn_reindexar_tablas_espaciales()` | | Si es igual a `bytes_antes` cada semana, se puede pasar a frecuencia mensual |

Un indice con `idx_scan = 0` despues de semanas de uso no lo esta usando ninguna consulta: ocupa espacio y
hace mas lentas las escrituras sin acelerar nada.
