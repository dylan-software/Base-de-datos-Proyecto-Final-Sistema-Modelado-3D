-- habitaciones.vertices stores the floor polygon as JSON and returns it unchanged; NULL is allowed
-- (rectangular rooms). Run on an empty database after schema.sql.
BEGIN;

DO $$
DECLARE
  polygon constant jsonb :=
    '[{"x": 0, "y": 0}, {"x": 4, "y": 0}, {"x": 4, "y": 3}, {"x": 2, "y": 3}, {"x": 2, "y": 5}, {"x": 0, "y": 5}]';
  room_id integer;
  rect_id integer;
  stored jsonb;
BEGIN
  INSERT INTO habitaciones (user_id, nombre, ancho, alto, profundidad, vertices)
  VALUES ('1', 'Sala en L', 4, 2.5, 5, polygon)
  RETURNING id INTO room_id;
  INSERT INTO habitaciones (user_id, nombre, ancho, alto, profundidad)
  VALUES ('1', 'Rectangular', 3, 2.5, 3)
  RETURNING id INTO rect_id;

  SELECT vertices INTO stored FROM habitaciones WHERE id = room_id;
  IF stored IS DISTINCT FROM polygon THEN
    RAISE EXCEPTION 'FAIL: test_habitaciones_vertices_json: read back % instead of %', stored, polygon;
  END IF;
  IF jsonb_typeof(stored) <> 'array' OR jsonb_array_length(stored) <> 6 THEN
    RAISE EXCEPTION 'FAIL: test_habitaciones_vertices_json: expected an array of 6 vertices, got %', stored;
  END IF;
  -- Order is kept: the fourth vertex is (2, 3).
  IF (stored -> 3 ->> 'x')::float <> 2 OR (stored -> 3 ->> 'y')::float <> 3 THEN
    RAISE EXCEPTION 'FAIL: test_habitaciones_vertices_json: vertex 3 is %, expected (2, 3)', stored -> 3;
  END IF;

  IF (SELECT vertices FROM habitaciones WHERE id = rect_id) IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: test_habitaciones_vertices_json: a room created without vertices is not NULL';
  END IF;

  RAISE NOTICE 'PASS: test_habitaciones_vertices_json';
END
$$;

ROLLBACK;
