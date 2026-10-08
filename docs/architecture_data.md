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
