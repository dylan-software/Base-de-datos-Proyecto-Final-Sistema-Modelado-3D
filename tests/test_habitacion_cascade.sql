-- Deleting a room deletes its placed furniture and nothing else (ON DELETE CASCADE). Run on an empty
-- database after schema.sql.
BEGIN;

DO $$
DECLARE
  room_a integer;
  room_b integer;
  left_a integer;
  left_b integer;
BEGIN
  INSERT INTO habitaciones (user_id, nombre, ancho, alto, profundidad) VALUES ('1', 'Sala', 4, 2.5, 5)
  RETURNING id INTO room_a;
  INSERT INTO habitaciones (user_id, nombre, ancho, alto, profundidad) VALUES ('1', 'Cuarto', 3, 2.5, 3)
  RETURNING id INTO room_b;

  INSERT INTO muebles_sugeridos (habitacion_id, nombre, ancho, alto, profundidad, posicion_x, posicion_y, posicion_z)
  VALUES (room_a, 'Sofa', 2, 0.9, 0.9, 1, 0, 0.45),
         (room_a, 'Mesa', 1, 0.5, 0.6, 2, 0, 2),
         (room_b, 'Cama', 1.4, 0.6, 2, 1.5, 0, 1);

  DELETE FROM habitaciones WHERE id = room_a;

  SELECT count(*) INTO left_a FROM muebles_sugeridos WHERE habitacion_id = room_a;
  SELECT count(*) INTO left_b FROM muebles_sugeridos WHERE habitacion_id = room_b;
  IF left_a <> 0 THEN
    RAISE EXCEPTION 'FAIL: test_habitacion_cascade: % pieces of the deleted room remain', left_a;
  END IF;
  IF left_b <> 1 THEN
    RAISE EXCEPTION 'FAIL: test_habitacion_cascade: the other room has % pieces, expected 1', left_b;
  END IF;

  RAISE NOTICE 'PASS: test_habitacion_cascade';
END
$$;

ROLLBACK;
