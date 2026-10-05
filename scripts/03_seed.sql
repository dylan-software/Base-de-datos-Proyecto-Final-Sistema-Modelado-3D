-- Datos semilla para pruebas. Ejecutar despues de 02_indexes.sql.

-- Habitacion vacia de 4 x 4 metros con 2.5 m de alto.
INSERT INTO habitaciones (id, nombre, alto, ancho, profundidad)
VALUES (1, 'Habitacion de prueba 4x4', 2.5, 4.0, 4.0);

SELECT setval('habitaciones_id_seq', (SELECT MAX(id) FROM habitaciones));
