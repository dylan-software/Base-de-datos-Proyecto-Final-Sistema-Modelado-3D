-- =====================================================================================================
-- !!!                         DESTRUCTIVE ROLLBACK - READ BEFORE RUNNING                            !!!
-- =====================================================================================================
-- Rollback of migration 005: removes grupos_proyecto and habitaciones.grupo_id, habitaciones.descripcion
-- and habitaciones.derivado_de.
--
-- This PERMANENTLY DELETES every project group (name and description), the link of each project to its
-- group and every project description. Projects (habitaciones) and their furniture are NOT deleted. Nothing
-- can bring the groups or descriptions back except a backup. The current backend also re-creates the table
-- and the columns (empty) at its next startup, so this is only useful together with a rollback of the
-- backend to a version without groups.
--
-- As shipped, this file only REPORTS what would be lost. To really drop everything:
--   1. Take a backup (Supabase: Database -> Backups, or pg_dump).
--   2. Run this file and read the counts it returns.
--   3. Remove the leading "-- " from the lines between BEGIN and COMMIT below and run the file again.
-- =====================================================================================================

-- What would be lost. Read-only. Fails if migration 005 was never applied: then there is nothing to undo.
SELECT (SELECT count(*) FROM grupos_proyecto) AS groups_total,
       count(*) FILTER (WHERE grupo_id IS NOT NULL) AS rooms_in_a_group,
       count(*) FILTER (WHERE descripcion IS NOT NULL) AS rooms_with_description,
       count(*) AS rooms_total
FROM habitaciones;

BEGIN;
-- DROP INDEX IF EXISTS ix_habitaciones_grupo_id;
-- ALTER TABLE habitaciones DROP COLUMN IF EXISTS derivado_de;
-- ALTER TABLE habitaciones DROP COLUMN IF EXISTS descripcion;
-- ALTER TABLE habitaciones DROP COLUMN IF EXISTS grupo_id;
-- DROP TABLE IF EXISTS grupos_proyecto;
COMMIT;
