-- Migration 001: owning account on rooms and catalog items.
--
-- For databases whose tables were created by the FastAPI backend (create_all) before user_id existed.
-- create_all never alters an existing table, so those tables lack the column. The backend also adds it
-- at startup (add_missing_user_columns in app/database/connection.py); this file does the same by hand
-- so the change can be reviewed and applied before deploying.
--
-- Idempotent and plain SQL: safe to run again, runs as is in the Supabase SQL Editor.
-- Rows that existed before have user_id NULL and are not listed for any account.

BEGIN;

ALTER TABLE muebles_catalogo ADD COLUMN IF NOT EXISTS user_id VARCHAR(64);
CREATE INDEX IF NOT EXISTS ix_muebles_catalogo_user_id ON muebles_catalogo (user_id);

ALTER TABLE habitaciones ADD COLUMN IF NOT EXISTS user_id VARCHAR(64);
CREATE INDEX IF NOT EXISTS ix_habitaciones_user_id ON habitaciones (user_id);

COMMIT;
