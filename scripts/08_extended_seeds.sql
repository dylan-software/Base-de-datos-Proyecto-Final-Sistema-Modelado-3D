-- Escenarios de prueba con medidas reales. Ejecutar despues de
-- procedures/sp_room_analytics.sql: cada mueble pasa por el trigger
-- trg_muebles_limites_check, asi que una coordenada mal calculada hace
-- fallar el script en lugar de guardar un layout imposible.
--
-- Convencion: X -> ancho, Y -> alto, Z -> profundidad (metros). La
-- posicion es el centro de la base del mueble. Las habitaciones quedan a
-- nombre de la cuenta "sistema" de 04_security.sql, y cada bloque usa
-- currval() para tomar el id de la habitacion recien insertada.

-- ---------------------------------------------------------------------
-- Oficina Moderna: 3 m x 3 m con 2.4 m de alto.
-- El escritorio va contra la pared del fondo (Z = 0), la silla delante de
-- el y el estante flotante sobre el escritorio, a 1.5 m del piso.
-- ---------------------------------------------------------------------
INSERT INTO habitaciones (nombre, alto, ancho, profundidad, usuario_id)
VALUES ('Oficina Moderna', 2.4, 3.0, 3.0,
        (SELECT id FROM usuarios WHERE nombre_usuario = 'sistema'));

INSERT INTO muebles_sugeridos
  (habitacion_id, nombre, posicion_x, posicion_y, posicion_z, ancho, alto, profundidad)
VALUES
  -- Z = 0.6 / 2: el fondo del escritorio toca la pared.
  (currval('habitaciones_id_seq'), 'Escritorio',         1.5, 0.0, 0.30,  1.20, 0.75, 0.60),
  -- Z = 0.6 + 0.6 / 2: la silla empieza donde termina el escritorio.
  (currval('habitaciones_id_seq'), 'Silla ergonomica',   1.5, 0.0, 0.90,  0.60, 1.10, 0.60),
  (currval('habitaciones_id_seq'), 'Estante flotante',   1.5, 1.5, 0.125, 0.90, 0.25, 0.25);

-- ---------------------------------------------------------------------
-- Dormitorio Principal: 4.5 m de ancho, 4 m de profundidad y 2.6 m de alto.
-- La cama king (1.93 x 2.03 m) apoya la cabecera en la pared del fondo y
-- queda centrada en X; cada mesa de noche deja 5 cm de holgura con ella:
--   X = 2.25 +/- (1.93 / 2 + 0.05 + 0.50 / 2) = 2.25 +/- 1.265
-- El armario empotrado ocupa la pared opuesta (Z = 4.0 - 0.6 / 2).
-- ---------------------------------------------------------------------
INSERT INTO habitaciones (nombre, alto, ancho, profundidad, usuario_id)
VALUES ('Dormitorio Principal', 2.6, 4.5, 4.0,
        (SELECT id FROM usuarios WHERE nombre_usuario = 'sistema'));

INSERT INTO muebles_sugeridos
  (habitacion_id, nombre, posicion_x, posicion_y, posicion_z, ancho, alto, profundidad)
VALUES
  (currval('habitaciones_id_seq'), 'Cama king',           2.250, 0.0, 1.015, 1.93, 0.60, 2.03),
  (currval('habitaciones_id_seq'), 'Mesa de noche izq.',  0.985, 0.0, 0.200, 0.50, 0.55, 0.40),
  (currval('habitaciones_id_seq'), 'Mesa de noche der.',  3.515, 0.0, 0.200, 0.50, 0.55, 0.40),
  (currval('habitaciones_id_seq'), 'Armario empotrado',   1.200, 0.0, 3.700, 2.00, 2.40, 0.60);

-- ---------------------------------------------------------------------
-- Sala de Estar Minimalista: 5 m x 4 m con 2.7 m de alto.
-- Las coordenadas no se escriben a mano: se calculan a partir de las
-- medidas de la habitacion (h), de modo que el layout sigue siendo
-- valido si se cambian alto/ancho/profundidad en el INSERT.
--   centro de la sala:  (cx, cz) = (ancho / 2, profundidad / 2)
--   mueble contra pared: Z = su profundidad / 2   o   Z = profundidad - p / 2
--   butacas: sobre un circulo de radio r = 1.6 m alrededor de la mesa,
--            en los angulos 0 y 180 grados -> (cx + r cos t, cz + r sin t)
-- ---------------------------------------------------------------------
INSERT INTO habitaciones (nombre, alto, ancho, profundidad, usuario_id)
VALUES ('Sala de Estar Minimalista', 2.7, 5.0, 4.0,
        (SELECT id FROM usuarios WHERE nombre_usuario = 'sistema'));

INSERT INTO muebles_sugeridos
  (habitacion_id, nombre, posicion_x, posicion_y, posicion_z, ancho, alto, profundidad)
SELECT h.id, m.nombre, m.x, m.y, m.z, m.ancho, m.alto, m.profundidad
FROM habitaciones h
CROSS JOIN LATERAL (
  VALUES
    ('Sofa de tres puestos', h.ancho / 2,                          0.0::FLOAT, 0.90 / 2,
                             2.20::FLOAT, 0.80::FLOAT, 0.90::FLOAT),
    ('Mesa de centro',       h.ancho / 2,                          0.0,        h.profundidad / 2,
                             1.00,        0.40,        0.60),
    ('Alfombra',             h.ancho / 2,                          0.0,        h.profundidad / 2,
                             2.00,        0.01,        1.40),
    ('Mueble de TV',         h.ancho / 2,                          0.0,        h.profundidad - 0.40 / 2,
                             1.80,        0.50,        0.40),
    ('Butaca oeste',         h.ancho / 2 + 1.6 * cos(radians(180)), 0.0,       h.profundidad / 2 + 1.6 * sin(radians(180)),
                             0.80,        0.80,        0.80),
    ('Butaca este',          h.ancho / 2 + 1.6 * cos(radians(0)),   0.0,       h.profundidad / 2 + 1.6 * sin(radians(0)),
                             0.80,        0.80,        0.80),
    -- Esquina del fondo a la derecha, a 0.3 m de ambas paredes.
    ('Lampara de pie',       h.ancho - 0.30,                       0.0,        0.30,
                             0.30,        1.60,        0.30)
) AS m (nombre, x, y, z, ancho, alto, profundidad)
WHERE h.id = currval('habitaciones_id_seq');
