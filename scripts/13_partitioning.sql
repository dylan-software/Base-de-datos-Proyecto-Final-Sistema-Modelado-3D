-- Particionamiento nativo por rango de fechas de historial_ia. Ejecutar
-- despues de 12_db_maintenance.sql. Funciona en PostgreSQL local (12+) y
-- en Supabase.
--
-- historial_ia solo crece: cada recomendacion de OmniRoute es una fila
-- nueva y el frontend casi siempre lee las mas recientes. Partida por
-- creado_en, una consulta con filtro de fecha lee solo las particiones de
-- ese rango (partition pruning), y un periodo viejo se archiva o se borra
-- con DETACH/DROP PARTITION en vez de un DELETE masivo seguido de VACUUM.
--
-- PostgreSQL no convierte una tabla existente en particionada: el script
-- renombra la actual, crea la nueva con el mismo nombre, copia las filas y
-- borra la anterior. Todo va en una sola transaccion: si algo falla, la
-- tabla original queda intacta. Se ejecuta una sola vez.

BEGIN;

COMMIT;
