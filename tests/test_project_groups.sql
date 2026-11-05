-- Project groups (migration 005): deleting a group or a source project never deletes a project, the
-- descriptions are limited to 1000 characters and a group needs its owner. Run on an empty database
-- after schema.sql.
BEGIN;

DO $$
DECLARE
  group_id integer;
  room_id integer;
  derived_id integer;
  left_group integer;
  left_source integer;
  rooms_left integer;
BEGIN
  INSERT INTO grupos_proyecto (user_id, nombre, descripcion) VALUES ('1', 'Casa', 'Sala y comedor')
  RETURNING id INTO group_id;
  INSERT INTO habitaciones (user_id, nombre, ancho, alto, profundidad, grupo_id, descripcion)
  VALUES ('1', 'Prueba 1', 4, 2.5, 3, group_id, 'Sofa contra la pared')
  RETURNING id INTO room_id;
  INSERT INTO habitaciones (user_id, nombre, ancho, alto, profundidad, grupo_id, derivado_de)
  VALUES ('1', 'Prueba 2', 4, 2.5, 3, group_id, room_id)
  RETURNING id INTO derived_id;

  -- 1000 characters are accepted in both descriptions.
  UPDATE grupos_proyecto SET descripcion = repeat('a', 1000) WHERE id = group_id;
  UPDATE habitaciones SET descripcion = repeat('b', 1000) WHERE id = room_id;

  -- 1001 characters are rejected by the named CHECK constraints.
  BEGIN
    UPDATE grupos_proyecto SET descripcion = repeat('a', 1001) WHERE id = group_id;
    RAISE EXCEPTION 'FAIL: test_project_groups: a group description of 1001 characters was accepted';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
  BEGIN
    UPDATE habitaciones SET descripcion = repeat('b', 1001) WHERE id = room_id;
    RAISE EXCEPTION 'FAIL: test_project_groups: a project description of 1001 characters was accepted';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  -- A group always has an owner.
  BEGIN
    INSERT INTO grupos_proyecto (user_id, nombre) VALUES (NULL, 'Sin dueno');
    RAISE EXCEPTION 'FAIL: test_project_groups: a group without user_id was accepted';
  EXCEPTION WHEN not_null_violation THEN
    NULL;
  END;

  -- Deleting the group leaves its projects without a group, but keeps them.
  DELETE FROM grupos_proyecto WHERE id = group_id;
  SELECT count(*) INTO left_group FROM habitaciones WHERE id IN (room_id, derived_id) AND grupo_id IS NOT NULL;
  SELECT count(*) INTO rooms_left FROM habitaciones WHERE id IN (room_id, derived_id);
  IF rooms_left <> 2 THEN
    RAISE EXCEPTION 'FAIL: test_project_groups: deleting a group deleted % of its 2 projects', 2 - rooms_left;
  END IF;
  IF left_group <> 0 THEN
    RAISE EXCEPTION 'FAIL: test_project_groups: % projects still point to the deleted group', left_group;
  END IF;

  -- Deleting the source project leaves the derived one without derivado_de, but keeps it.
  DELETE FROM habitaciones WHERE id = room_id;
  SELECT count(*) INTO left_source FROM habitaciones WHERE id = derived_id AND derivado_de IS NULL;
  IF left_source <> 1 THEN
    RAISE EXCEPTION 'FAIL: test_project_groups: the derived project was deleted or still points to its source';
  END IF;

  RAISE NOTICE 'PASS: test_project_groups';
END
$$;

ROLLBACK;
