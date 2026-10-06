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
