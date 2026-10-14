-- Particionamiento nativo por rango de fechas de historial_ia. Ejecutar
-- despues de 12_db_maintenance.sql. Funciona en PostgreSQL local (12+) y
-- en Supabase.
--
-- historial_ia solo crece: cada recomendacion de OmniRoute es una fila
-- nueva y el frontend casi siempre lee las mas recientes. Partida por
-- creado_en, una consulta con filtro de fecha lee solo las particiones de
-- ese rango (partition pruning), y un periodo viejo se archiva o se borra
-- con DETACH/DROP PARTITION en vez de un DELETE masivo seguido de VACUUM.
--
-- PostgreSQL no convierte una tabla existente en particionada: el script
-- renombra la actual, crea la nueva con el mismo nombre, copia las filas y
-- borra la anterior. Todo va en una sola transaccion: si algo falla, la
-- tabla original queda intacta. Se ejecuta una sola vez.

BEGIN;

-- La tabla actual se aparta con otro nombre. Su indice de llave primaria
-- tambien, para que la tabla nueva pueda usar historial_ia_pkey.
ALTER TABLE historial_ia RENAME TO historial_ia_legacy;
ALTER INDEX historial_ia_pkey RENAME TO historial_ia_legacy_pkey;

-- Mismas columnas que en 01_schema.sql, particionada por rangos anuales de
-- creado_en. La llave primaria de una tabla particionada tiene que incluir
-- la columna de particion, por eso pasa a ser (id, creado_en); id sigue
-- saliendo de la misma secuencia, asi que no se repite. Cada rango es
-- [desde, hasta): una fila con creado_en justo en el limite va a la
-- particion siguiente.
CREATE TABLE historial_ia (
  id             INTEGER NOT NULL DEFAULT nextval('historial_ia_id_seq'),
  habitacion_id  INTEGER NOT NULL REFERENCES habitaciones(id) ON DELETE CASCADE,
  recomendacion  TEXT NOT NULL,
  creado_en      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (id, creado_en)
) PARTITION BY RANGE (creado_en);

-- Recomendaciones recientes de una habitacion. El indice se declara en la
-- tabla padre y PostgreSQL lo crea en cada particion, tambien en las que se
-- agreguen despues.
CREATE INDEX idx_historial_ia_habitacion
  ON historial_ia (habitacion_id, creado_en DESC);

-- Recibe las filas que no caen en ningun rango: el historial de los anos
-- anteriores y cualquier fecha para la que todavia no exista particion.
-- Sin ella, un INSERT asi fallaria con "no partition of relation found".
CREATE TABLE historial_ia_default PARTITION OF historial_ia DEFAULT;

-- Periodo actual: el ano 2026, que contiene el semestre en curso (2026-2).
-- Va antes de copiar las filas: si se creara despues, las de 2026 ya
-- estarian en historial_ia_default y PostgreSQL rechazaria la particion.
-- Los limites llevan +00 para no depender de la zona horaria de la sesion.
-- Al empezar cada ano se crea la siguiente (ver docs/maintenance_guide.md).
CREATE TABLE historial_ia_2026 PARTITION OF historial_ia
  FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2027-01-01 00:00:00+00');

-- Copia: cada fila cae sola en su particion segun creado_en.
INSERT INTO historial_ia (id, habitacion_id, recomendacion, creado_en)
SELECT id, habitacion_id, recomendacion, creado_en
FROM historial_ia_legacy;

-- La secuencia pertenecia a historial_ia_legacy.id y se borraria con ella:
-- pasa a pertenecer a la tabla nueva antes del DROP.
ALTER SEQUENCE historial_ia_id_seq OWNED BY historial_ia.id;

DROP TABLE historial_ia_legacy;

COMMIT;
