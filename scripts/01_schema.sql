-- Esquema relacional local (PostgreSQL) para la aplicacion de modelado 3D.
-- Ejecutar con psql: crea la base de datos y se conecta a ella.
CREATE DATABASE modelado_3d;

\c modelado_3d

-- Habitaciones escaneadas/modeladas. Dimensiones en metros.
CREATE TABLE habitaciones (
  id           SERIAL PRIMARY KEY,
  nombre       VARCHAR(100) NOT NULL,
  alto         FLOAT NOT NULL CHECK (alto > 0),
  ancho        FLOAT NOT NULL CHECK (ancho > 0),
  profundidad  FLOAT NOT NULL CHECK (profundidad > 0),
  creado_en    TIMESTAMPTZ NOT NULL DEFAULT now()
);
