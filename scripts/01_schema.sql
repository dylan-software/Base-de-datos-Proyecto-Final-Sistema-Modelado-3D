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

-- Muebles sugeridos y validados por el Octree. Posicion cartesiana en
-- metros relativa al origen de la habitacion.
CREATE TABLE muebles_sugeridos (
  id             SERIAL PRIMARY KEY,
  habitacion_id  INTEGER NOT NULL,
  nombre         VARCHAR(100) NOT NULL,
  posicion_x     FLOAT NOT NULL,
  posicion_y     FLOAT NOT NULL,
  posicion_z     FLOAT NOT NULL,
  creado_en      TIMESTAMPTZ NOT NULL DEFAULT now()
);
