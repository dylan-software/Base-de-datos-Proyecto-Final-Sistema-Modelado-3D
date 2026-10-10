-- Prueba matematica de fn_distancia_euclidiana (06_advanced_queries.sql).
-- Funciona en PostgreSQL local y en Supabase. Solo lee: no necesita
-- transaccion ni deja datos.
--
-- Caso principal: P1 = (1, 1, 1) y P2 = (4, 5, 1).
--   d = sqrt((4 - 1)^2 + (5 - 1)^2 + (1 - 1)^2)
--     = sqrt(9 + 16 + 0)
--     = sqrt(25) = 5
-- Es el triangulo 3-4-5 sobre el plano Z = 1. Como 25 es un cuadrado
-- perfecto, sqrt() en FLOAT devuelve 5 exacto y se puede comparar con =.
-- El resto de los casos usa una tolerancia de 1e-9.

DO $$
DECLARE
  c_tol  CONSTANT FLOAT := 1e-9;
  v_d    FLOAT;
BEGIN
  -- Caso 1: vectores (1, 1, 1) y (4, 5, 1).
  v_d := fn_distancia_euclidiana(1, 1, 1, 4, 5, 1);
  ASSERT v_d = 5, format('d((1,1,1), (4,5,1)) = %s; se esperaba 5', v_d);
  RAISE NOTICE 'OK d((1,1,1), (4,5,1)) = %', v_d;

  -- Caso 2: simetria, d(P1, P2) = d(P2, P1).
  ASSERT fn_distancia_euclidiana(4, 5, 1, 1, 1, 1) = v_d,
         'la distancia no es simetrica';
  RAISE NOTICE 'OK simetria d(P1, P2) = d(P2, P1)';

  -- Caso 3: distancia de un punto a si mismo.
  ASSERT fn_distancia_euclidiana(1, 1, 1, 1, 1, 1) = 0,
         'd(P, P) deberia ser 0';
  RAISE NOTICE 'OK d(P, P) = 0';

  -- Caso 4: diferencia en los tres ejes. (0,0,0) a (1,2,2): sqrt(1+4+4) = 3.
  v_d := fn_distancia_euclidiana(0, 0, 0, 1, 2, 2);
  ASSERT abs(v_d - 3) < c_tol, format('d((0,0,0), (1,2,2)) = %s; se esperaba 3', v_d);
  RAISE NOTICE 'OK d((0,0,0), (1,2,2)) = %', v_d;

  -- Caso 5: coordenadas negativas. (-1,-1,-1) a (1,1,1): sqrt(12) = 2*sqrt(3).
  v_d := fn_distancia_euclidiana(-1, -1, -1, 1, 1, 1);
  ASSERT abs(v_d - 2 * sqrt(3)) < c_tol,
         format('d((-1,-1,-1), (1,1,1)) = %s; se esperaba %s', v_d, 2 * sqrt(3));
  RAISE NOTICE 'OK d((-1,-1,-1), (1,1,1)) = %', v_d;

  -- Caso 6: STRICT devuelve NULL si falta cualquier coordenada.
  ASSERT fn_distancia_euclidiana(1, 1, NULL, 4, 5, 1) IS NULL,
         'con una coordenada NULL deberia devolver NULL';
  RAISE NOTICE 'OK coordenada NULL -> NULL';

  -- Caso 7: la funcion esta declarada IMMUTABLE y STRICT.
  ASSERT (SELECT provolatile = 'i' AND proisstrict
          FROM pg_proc
          WHERE oid = 'fn_distancia_euclidiana(float, float, float, float, float, float)'::regprocedure),
         'fn_distancia_euclidiana deberia ser IMMUTABLE y STRICT';
  RAISE NOTICE 'OK test_funcion_distancia_euclidiana: todas las aserciones superadas';
END;
$$;
