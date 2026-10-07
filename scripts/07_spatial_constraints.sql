-- Restricciones geometricas y espaciales. Ejecutar despues de
-- 06_advanced_queries.sql.
-- Garantiza que ningun mueble quede fuera de la caja de su habitacion.
--
-- Convencion de ejes (la misma de Three.js y de 03_seed.sql):
--   X -> ancho, Y -> alto (desde el piso), Z -> profundidad.
-- La posicion de un mueble es el centro de su base: centrado en X y Z,
-- apoyado sobre Y.

-- Medidas del mueble en metros. Son opcionales para no romper los muebles
-- existentes: si faltan, el mueble se valida como un punto.
ALTER TABLE muebles_sugeridos
  ADD COLUMN ancho        FLOAT CHECK (ancho > 0),
  ADD COLUMN alto         FLOAT CHECK (alto > 0),
  ADD COLUMN profundidad  FLOAT CHECK (profundidad > 0);
