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
