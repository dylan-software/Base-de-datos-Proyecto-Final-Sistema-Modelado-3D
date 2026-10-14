-- Datos semilla masivos para pruebas de carga. Ejecutar despues de
-- procedures/sp_vector_math.sql.
-- Simula un hotel: muchas habitaciones parecidas, cada una con unos pocos
-- muebles, para medir con EXPLAIN (ANALYZE) los indices de
-- 09_performance_indexes.sql y los triggers que corren en cada INSERT
-- (trg_impedir_superposicion y trg_muebles_limites_check).
--
-- Convencion: X -> ancho, Y -> alto, Z -> profundidad (metros). La
-- posicion es el centro de la base del mueble. Todo queda a nombre de la
-- cuenta "sistema" de 04_security.sql, y las habitaciones se reconocen por
-- el prefijo 'Hotel Estres - ' en su nombre.
-- Para borrar la simulacion (los muebles caen por ON DELETE CASCADE):
--   DELETE FROM habitaciones WHERE nombre LIKE 'Hotel Estres - %';

-- ---------------------------------------------------------------------
-- Hotel de 20 habitaciones, numeradas de forma correlativa
-- ('Hotel Estres - Habitacion 01' a '... 20') e insertadas en ese orden,
-- de modo que sus id tambien quedan consecutivos (salvo que otra sesion
-- inserte habitaciones al mismo tiempo).
-- Todas miden 2.6 m de alto y 5 m de profundidad; el ancho rota entre
-- 4, 5 y 6 m (ancho = 4 + i mod 3) para que no todas las plantas sean
-- iguales.
-- Si el hotel ya existe el bloque no hace nada: el script se puede volver
-- a ejecutar sin duplicar habitaciones.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  c_habitaciones  CONSTANT INTEGER := 20;
  v_usuario_id    INTEGER := (SELECT id FROM usuarios WHERE nombre_usuario = 'sistema');
BEGIN
  IF EXISTS (SELECT 1 FROM habitaciones WHERE nombre LIKE 'Hotel Estres - %') THEN
    RAISE NOTICE 'El hotel de estres ya existe; no se insertan habitaciones';
    RETURN;
  END IF;

  FOR i IN 1..c_habitaciones LOOP
    INSERT INTO habitaciones (nombre, alto, ancho, profundidad, usuario_id)
    VALUES (format('Hotel Estres - Habitacion %s', lpad(i::TEXT, 2, '0')),
            2.6, 4.0 + i % 3, 5.0, v_usuario_id);
  END LOOP;

  RAISE NOTICE 'Hotel de estres: % habitaciones insertadas', c_habitaciones;
END;
$$;

-- ---------------------------------------------------------------------
-- 50 muebles repartidos entre las 20 habitaciones del hotel.
-- El mueble n (1..50) va a la habitacion r = (n - 1) mod 20 + 1 y ocupa
-- en ella el puesto k = (n - 1) / 20 (division entera): las habitaciones
-- 01 a 10 reciben 3 muebles (k = 0, 1, 2) y las 11 a 20 reciben 2.
-- Cada puesto esta sobre la diagonal de la planta, a un cuarto, la mitad y
-- tres cuartos del recorrido:
--   X = ancho * (k + 1) / 4,   Y = 0,   Z = profundidad * (k + 1) / 4
-- Con ancho >= 4 y profundidad = 5, dos puestos seguidos quedan a 1.0 m en
-- X (o mas, en las plantas de 5 y 6 m) y 1.25 m en Z: lejos del radio de
-- 0.10 m de trg_impedir_superposicion, y en Z las cajas no se tocan
-- porque la mayor profundidad del catalogo es 0.8 m.
-- El tipo de mueble es (n + k) mod 5. Sumar k evita que los muebles n,
-- n + 20 y n + 40, que caen en la misma habitacion, sean del mismo tipo.
-- Solo se llenan habitaciones del hotel que aun no tienen muebles, asi que
-- una segunda ejecucion no inserta nada.
-- ---------------------------------------------------------------------
INSERT INTO muebles_sugeridos
  (habitacion_id, nombre, posicion_x, posicion_y, posicion_z, ancho, alto, profundidad)
SELECT h.id,
       format('%s %s-%s', t.nombre, lpad(h.numero::TEXT, 2, '0'), p.k + 1),
       h.ancho * (p.k + 1) / 4,
       0.0,
       h.profundidad * (p.k + 1) / 4,
       t.ancho, t.alto, t.profundidad
FROM generate_series(1, 50) AS g(n)
CROSS JOIN LATERAL (
  SELECT (g.n - 1) % 20 + 1         AS habitacion,
         (g.n - 1) / 20             AS k,
         (g.n + (g.n - 1) / 20) % 5 AS tipo
) AS p
JOIN (
  SELECT hab.id, hab.ancho, hab.profundidad,
         row_number() OVER (ORDER BY hab.id) AS numero
  FROM habitaciones hab
  WHERE hab.nombre LIKE 'Hotel Estres - %'
) AS h ON h.numero = p.habitacion
JOIN (
  VALUES
    (0, 'Escritorio',    1.20::FLOAT, 0.75::FLOAT, 0.60::FLOAT),
    (1, 'Silla',         0.50,        0.90,        0.50),
    (2, 'Mesa de noche', 0.50,        0.55,        0.40),
    (3, 'Armario',       1.00,        2.00,        0.60),
    (4, 'Butaca',        0.80,        0.80,        0.80)
) AS t (tipo, nombre, ancho, alto, profundidad) ON t.tipo = p.tipo
WHERE NOT EXISTS (
  SELECT 1 FROM muebles_sugeridos m WHERE m.habitacion_id = h.id
)
ORDER BY g.n;
