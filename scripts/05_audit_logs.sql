-- Auditoria de la interfaz web. Ejecutar despues de 04_security.sql.
-- Guarda la actividad de las sesiones y el historial de posiciones 3D.

-- TODO: tablas de auditoria.

-- Bitacora general: inicios/cierres de sesion y peticiones asincronas que
-- el navegador hace a la API de Python. usuario_id es opcional porque un
-- login fallido puede no corresponder a ningun usuario existente.
CREATE TABLE logs_actividad (
  id             BIGSERIAL PRIMARY KEY,
  usuario_id     INTEGER REFERENCES usuarios(id) ON DELETE SET NULL,
  tipo_evento    VARCHAR(20) NOT NULL
                 CHECK (tipo_evento IN ('login', 'login_fallido', 'logout', 'peticion_api')),
  metodo_http    VARCHAR(10),
  endpoint       VARCHAR(255),
  codigo_estado  SMALLINT,
  ip_origen      INET,
  creado_en      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_logs_actividad_usuario
  ON logs_actividad (usuario_id, creado_en);

-- Historial de posiciones de cada mueble: coordenadas antes (old_*) y
-- despues (new_*) de cada cambio, por ejemplo cuando la IA de OmniRoute
-- reubica un objeto. La llena el trigger de procedures/sp_triggers.sql.
-- modificado_por se toma de la variable de sesion app.usuario_id.
CREATE TABLE auditoria_muebles (
  id              BIGSERIAL PRIMARY KEY,
  mueble_id       INTEGER NOT NULL REFERENCES muebles_sugeridos(id) ON DELETE CASCADE,
  old_x           FLOAT NOT NULL,
  old_y           FLOAT NOT NULL,
  old_z           FLOAT NOT NULL,
  new_x           FLOAT NOT NULL,
  new_y           FLOAT NOT NULL,
  new_z           FLOAT NOT NULL,
  modificado_por  INTEGER REFERENCES usuarios(id) ON DELETE SET NULL,
  modificado_en   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_auditoria_muebles_mueble
  ON auditoria_muebles (mueble_id, modificado_en);
