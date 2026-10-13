-- Indices de rendimiento. Ejecutar despues de 01_schema.sql.
-- PostgreSQL no indexa automaticamente las llaves foraneas: este indice
-- acelera la carga de todos los muebles de una habitacion.
CREATE INDEX idx_muebles_habitacion
  ON muebles_sugeridos (habitacion_id);
