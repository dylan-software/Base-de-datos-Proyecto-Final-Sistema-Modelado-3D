-- =====================================================================================================
-- !!!                         DESTRUCTIVE ROLLBACK - READ BEFORE RUNNING                            !!!
-- =====================================================================================================
-- Rollback of migration 006: removes publicaciones_proyecto.
--
-- This PERMANENTLY DELETES every publication of the social network (title, public description, frozen
-- copy and copy counter). Projects (habitaciones), their furniture and the projects people already copied
-- are NOT deleted: a copy is an ordinary project of the account that made it. Nothing can bring the
-- publications back except a backup. The current backend also re-creates the table (empty) at its next
-- startup, so this is only useful together with a rollback of the backend to a version without the social
-- network.
--
-- As shipped, this file only REPORTS what would be lost. To really drop everything:
--   1. Take a backup (Supabase: Database -> Backups, or pg_dump).
--   2. Run this file and read the counts it returns.
--   3. Remove the leading "-- " from the lines between BEGIN and COMMIT below and run the file again.
-- =====================================================================================================

-- What would be lost. Read-only. Fails if migration 006 was never applied: then there is nothing to undo.
SELECT count(*) AS publications_total,
       count(*) FILTER (WHERE publica) AS publications_public,
       coalesce(sum(copias), 0) AS copies_total
FROM publicaciones_proyecto;

BEGIN;
-- DROP INDEX IF EXISTS ix_publicaciones_proyecto_catalogo;
-- DROP INDEX IF EXISTS ix_publicaciones_proyecto_user_id;
-- DROP TABLE IF EXISTS publicaciones_proyecto;
COMMIT;
