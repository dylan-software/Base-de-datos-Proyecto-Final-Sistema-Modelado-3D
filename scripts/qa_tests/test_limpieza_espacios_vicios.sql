-- Prueba de mantenimiento: fn_purgar_habitaciones_vacias
-- (procedures/sp_maintenance.sql) borra solo las habitaciones vacias y
-- antiguas, arrastra su historial_ia por ON DELETE CASCADE y no queda
-- expuesta como RPC. Funciona en PostgreSQL local y en Supabase.
--
-- Escenario (margen por defecto de 7 dias):
--   A) vacia, creada hace 30 dias, con una recomendacion -> se borra
--   B) vacia, creada ahora                               -> se conserva
--   C) con un mueble, creada hace 30 dias                -> se conserva
--
-- IMPORTANTE: la funcion purga toda la tabla, no solo el fixture. Este
-- script debe correr completo para que el ROLLBACK final deshaga tambien
-- el borrado de las habitaciones reales que cumplan la condicion.

BEGIN;

INSERT INTO usuarios (nombre_usuario, email, password_hash)
VALUES ('qa_purga', 'qa_purga@modelado3d.local', 'qa-sin-login');

INSERT INTO habitaciones (nombre, alto, ancho, profundidad, usuario_id, creado_en)
VALUES
  ('QA purga A vacia antigua',      2.5, 3.0, 3.0, currval('usuarios_id_seq'), now() - INTERVAL '30 days'),
  ('QA purga B vacia reciente',     2.5, 3.0, 3.0, currval('usuarios_id_seq'), now()),
  ('QA purga C con mueble antigua', 2.5, 3.0, 3.0, currval('usuarios_id_seq'), now() - INTERVAL '30 days');

INSERT INTO historial_ia (habitacion_id, recomendacion)
SELECT id, 'QA recomendacion de prueba'
FROM habitaciones
WHERE nombre = 'QA purga A vacia antigua';

INSERT INTO muebles_sugeridos (habitacion_id, nombre, posicion_x, posicion_y, posicion_z)
SELECT id, 'QA lampara', 1.5, 0.0, 1.5
FROM habitaciones
WHERE nombre = 'QA purga C con mueble antigua';

DO $$
DECLARE
  v_id_a     INTEGER := (SELECT id FROM habitaciones WHERE nombre = 'QA purga A vacia antigua');
  v_borradas INTEGER;
BEGIN
  v_borradas := fn_purgar_habitaciones_vacias();

  -- Puede borrar mas de una si la base ya tenia habitaciones vacias
  -- antiguas; como minimo debe contar la del fixture.
  ASSERT v_borradas >= 1, format('la funcion reporto %s borradas; se esperaba al menos 1', v_borradas);
  RAISE NOTICE 'OK purga ejecutada: % habitaciones borradas', v_borradas;

  ASSERT NOT EXISTS (SELECT 1 FROM habitaciones WHERE id = v_id_a),
         'la habitacion vacia antigua no se borro';
  ASSERT NOT EXISTS (SELECT 1 FROM historial_ia WHERE habitacion_id = v_id_a),
         'el historial_ia de la habitacion borrada quedo huerfano';
  RAISE NOTICE 'OK A borrada junto con su historial_ia';

  ASSERT EXISTS (SELECT 1 FROM habitaciones WHERE nombre = 'QA purga B vacia reciente'),
         'se borro una habitacion vacia dentro del margen de 7 dias';
  RAISE NOTICE 'OK B conservada por el margen de antiguedad';

  ASSERT EXISTS (SELECT 1 FROM habitaciones WHERE nombre = 'QA purga C con mueble antigua'),
         'se borro una habitacion que tenia muebles';
  RAISE NOTICE 'OK C conservada por tener muebles';

  -- Una segunda ejecucion no encuentra nada mas que borrar.
  ASSERT fn_purgar_habitaciones_vacias() = 0, 'la purga no es idempotente';
  RAISE NOTICE 'OK segunda ejecucion: 0 borradas';

  -- En Supabase la funcion no debe poder llamarse por la API REST.
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    ASSERT NOT has_function_privilege('anon', 'fn_purgar_habitaciones_vacias(interval)', 'EXECUTE'),
           'anon puede ejecutar la purga';
    ASSERT NOT has_function_privilege('authenticated', 'fn_purgar_habitaciones_vacias(interval)', 'EXECUTE'),
           'authenticated puede ejecutar la purga';
    RAISE NOTICE 'OK EXECUTE revocado a anon y authenticated';
  END IF;

  RAISE NOTICE 'OK test_limpieza_espacios_vicios: todas las aserciones superadas';
END;
$$;

ROLLBACK;
