-- A catalog item must point to an existing category. Run on an empty database after schema.sql.
BEGIN;

DO $$
DECLARE
  cat_id integer;
BEGIN
  -- No category has a negative id: SERIAL starts at 1.
  BEGIN
    INSERT INTO muebles_catalogo (user_id, categoria_id, nombre, ancho, alto, profundidad)
    VALUES ('1', -1, 'Silla', 45, 90, 50);
    RAISE EXCEPTION 'FAIL: test_catalogo_requires_categoria: an unknown categoria_id was accepted';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO muebles_catalogo (user_id, categoria_id, nombre, ancho, alto, profundidad)
    VALUES ('1', NULL, 'Silla', 45, 90, 50);
    RAISE EXCEPTION 'FAIL: test_catalogo_requires_categoria: a NULL categoria_id was accepted';
  EXCEPTION WHEN not_null_violation THEN
    NULL;
  END;

  -- With an existing category the same item is accepted.
  INSERT INTO categorias (nombre) VALUES ('Asientos') RETURNING id INTO cat_id;
  INSERT INTO muebles_catalogo (user_id, categoria_id, nombre, ancho, alto, profundidad)
  VALUES ('1', cat_id, 'Silla', 45, 90, 50);

  RAISE NOTICE 'PASS: test_catalogo_requires_categoria';
END
$$;

ROLLBACK;
