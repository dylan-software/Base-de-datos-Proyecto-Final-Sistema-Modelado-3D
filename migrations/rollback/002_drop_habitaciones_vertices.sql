-- =====================================================================================================
-- !!!                         DESTRUCTIVE ROLLBACK - READ BEFORE RUNNING                            !!!
-- =====================================================================================================
-- Rollback of migration 002: removes habitaciones.vertices.
--
-- Dropping the column PERMANENTLY DELETES the floor polygon of every irregular room. Those rooms fall
-- back to the rectangle [0, ancho] x [0, profundidad], and nothing can bring the shapes back except a
-- backup. The current backend also re-adds the column (empty) at its next startup, so this is only
-- useful together with a rollback of the backend to a version without vertices.
--
-- As shipped, this file only REPORTS what would be lost. To really drop the column:
--   1. Take a backup (Supabase: Database -> Backups, or pg_dump).
--   2. Run this file and read the counts it returns.
--   3. Remove the leading "-- " from the ALTER TABLE line below and run the file again.
-- =====================================================================================================

-- Rooms whose polygon would be lost. Read-only.
SELECT count(*) FILTER (WHERE vertices IS NOT NULL) AS rooms_with_polygon,
       count(*) AS rooms_total
FROM habitaciones;

-- ALTER TABLE habitaciones DROP COLUMN IF EXISTS vertices;
