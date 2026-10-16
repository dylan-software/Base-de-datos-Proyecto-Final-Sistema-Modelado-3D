-- Migration 002: editable irregular floor polygon on rooms.
--
-- Adds habitaciones.vertices, a JSON array [{"x": m, "y": m}, ...] in meters. NULL keeps the old
-- meaning: the rectangle [0, ancho] x [0, profundidad]. The backend also adds the column at startup
-- (add_missing_room_columns in app/database/connection.py).
--
-- Idempotent and plain SQL. Undo with rollback/002_drop_habitaciones_vertices.sql (destructive).

BEGIN;

ALTER TABLE habitaciones ADD COLUMN IF NOT EXISTS vertices JSONB;

COMMIT;
