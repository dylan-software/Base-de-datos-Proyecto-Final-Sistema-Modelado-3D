-- =====================================================================================================
-- !!!                         DESTRUCTIVE ROLLBACK - READ BEFORE RUNNING                            !!!
-- =====================================================================================================
-- Rollback of migration 007: removes perfiles_publicos and the per-author catalog index.
--
-- This PERMANENTLY DELETES every public profile: its public code (old profile links stop working) and the
-- visible name each author typed. Publications, projects and their furniture are NOT deleted. Nothing can
-- bring the profiles back except a backup. The current backend also re-creates the table at its next
-- startup (with new codes and anonymous names), so this is only useful together with a rollback of the
-- backend to a version without profiles.
--
-- As shipped, this file only REPORTS what would be lost. To really drop everything:
--   1. Take a backup (Supabase: Database -> Backups, or pg_dump).
--   2. Run this file and read the counts it returns.
--   3. Remove the leading "-- " from the lines between BEGIN and COMMIT below and run the file again.
-- =====================================================================================================

-- What would be lost. Read-only. Fails if migration 007 was never applied: then there is nothing to undo.
SELECT count(*) AS profiles_total,
       count(nombre_visible) AS profiles_with_name
FROM perfiles_publicos;

BEGIN;
-- DROP INDEX IF EXISTS ix_publicaciones_proyecto_autor;
-- DROP TABLE IF EXISTS perfiles_publicos;
COMMIT;
