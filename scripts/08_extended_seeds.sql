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
