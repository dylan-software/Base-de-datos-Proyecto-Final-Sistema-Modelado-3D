-- Project publications (migration 006): private by default, one publication per project, unique public
-- codes, the named CHECKs, an owner is required, and deleting a project deletes its publication and
-- nothing else. Run on an empty database after schema.sql.
BEGIN;

DO $$
DECLARE
  room_id integer;
  other_room integer;
  pub_id integer;
  other_pub integer;
  is_public boolean;
  copies integer;
  left_pubs integer;
  rooms_left integer;
  doc jsonb := '{"format": "habita-project", "version": 1, "name": "Sala", "room": {"height_m": 2.5, "vertices": [[0, 0], [4, 0], [4, 3], [0, 3]], "estimated": false}, "items": []}';
BEGIN
  INSERT INTO habitaciones (user_id, nombre, ancho, alto, profundidad) VALUES ('1', 'Sala', 4, 2.5, 3)
  RETURNING id INTO room_id;
  INSERT INTO habitaciones (user_id, nombre, ancho, alto, profundidad) VALUES ('1', 'Cocina', 3, 2.5, 3)
  RETURNING id INTO other_room;

  -- A row inserted without publica is private, with no copies yet.
  INSERT INTO publicaciones_proyecto (codigo, user_id, habitacion_id, titulo, documento)
  VALUES ('AAAAAAAAAAAAAAAA', '1', room_id, 'Sala', doc)
  RETURNING id, publica, copias INTO pub_id, is_public, copies;
  IF is_public IS DISTINCT FROM false OR copies <> 0 THEN
    RAISE EXCEPTION 'FAIL: test_project_publications: a new row is not private with 0 copies';
  END IF;

  -- One publication per project.
  BEGIN
    INSERT INTO publicaciones_proyecto (codigo, user_id, habitacion_id, titulo, documento)
    VALUES ('BBBBBBBBBBBBBBBB', '1', room_id, 'Otra', doc);
    RAISE EXCEPTION 'FAIL: test_project_publications: a project was published twice';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  -- Public codes are unique.
  BEGIN
    INSERT INTO publicaciones_proyecto (codigo, user_id, habitacion_id, titulo, documento)
    VALUES ('AAAAAAAAAAAAAAAA', '1', other_room, 'Cocina', doc);
    RAISE EXCEPTION 'FAIL: test_project_publications: a repeated public code was accepted';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  -- 1000 characters of public description are accepted; 1001 are rejected.
  UPDATE publicaciones_proyecto SET descripcion = repeat('a', 1000), publica = true WHERE id = pub_id;
  BEGIN
    UPDATE publicaciones_proyecto SET descripcion = repeat('a', 1001) WHERE id = pub_id;
    RAISE EXCEPTION 'FAIL: test_project_publications: a description of 1001 characters was accepted';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  -- The copy counter is never negative.
  BEGIN
    UPDATE publicaciones_proyecto SET copias = -1 WHERE id = pub_id;
    RAISE EXCEPTION 'FAIL: test_project_publications: a negative copy counter was accepted';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  -- The frozen copy is at most 262144 characters as text.
  BEGIN
    UPDATE publicaciones_proyecto
    SET documento = jsonb_build_object('format', 'habita-project', 'padding', repeat('x', 262144))
    WHERE id = pub_id;
    RAISE EXCEPTION 'FAIL: test_project_publications: a document over 262144 characters was accepted';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  -- A publication always has an owner.
  BEGIN
    INSERT INTO publicaciones_proyecto (codigo, user_id, habitacion_id, titulo, documento)
    VALUES ('CCCCCCCCCCCCCCCC', NULL, other_room, 'Cocina', doc);
    RAISE EXCEPTION 'FAIL: test_project_publications: a publication without user_id was accepted';
  EXCEPTION WHEN not_null_violation THEN
    NULL;
  END;

  -- Deleting the project deletes its publication, and only that.
  INSERT INTO publicaciones_proyecto (codigo, user_id, habitacion_id, titulo, documento, publica)
  VALUES ('DDDDDDDDDDDDDDDD', '1', other_room, 'Cocina', doc, true)
  RETURNING id INTO other_pub;
  DELETE FROM habitaciones WHERE id = room_id;
  SELECT count(*) INTO left_pubs FROM publicaciones_proyecto WHERE id IN (pub_id, other_pub);
  SELECT count(*) INTO rooms_left FROM habitaciones WHERE id = other_room;
  IF left_pubs <> 1 OR NOT EXISTS (SELECT 1 FROM publicaciones_proyecto WHERE id = other_pub) THEN
    RAISE EXCEPTION 'FAIL: test_project_publications: deleting a project did not delete exactly its publication';
  END IF;
  IF rooms_left <> 1 THEN
    RAISE EXCEPTION 'FAIL: test_project_publications: deleting a project deleted another project';
  END IF;

  RAISE NOTICE 'PASS: test_project_publications';
END
$$;

ROLLBACK;
