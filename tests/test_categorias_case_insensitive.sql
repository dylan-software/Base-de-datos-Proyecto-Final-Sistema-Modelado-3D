-- Category names are unique ignoring case (uq_categorias_nombre_lower). Run on an empty database after
-- schema.sql.
BEGIN;

DO $$
DECLARE
  variant text;
BEGIN
  INSERT INTO categorias (nombre) VALUES ('Asientos');
  FOREACH variant IN ARRAY ARRAY['Asientos', 'asientos', 'ASIENTOS'] LOOP
    BEGIN
      INSERT INTO categorias (nombre) VALUES (variant);
      RAISE EXCEPTION 'FAIL: test_categorias_case_insensitive: "%" was accepted next to "Asientos"', variant;
    EXCEPTION WHEN unique_violation THEN
      NULL;
    END;
  END LOOP;

  -- A different name is still accepted.
  INSERT INTO categorias (nombre) VALUES ('Mesas');
  RAISE NOTICE 'PASS: test_categorias_case_insensitive';
END
$$;

ROLLBACK;
