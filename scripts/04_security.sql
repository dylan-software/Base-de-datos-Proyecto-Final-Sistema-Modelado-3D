-- Seguridad y control de accesos. Ejecutar despues de 03_seed.sql.
-- Modela usuarios, roles y la relacion de cada habitacion con su dueno.

-- Cuentas de acceso a la aplicacion web. La contrasena nunca se guarda en
-- claro: password_hash contiene la firma bcrypt generada con
-- crypt(<clave>, gen_salt('bf')) de pgcrypto.
CREATE TABLE usuarios (
  id              SERIAL PRIMARY KEY,
  nombre_usuario  VARCHAR(50) NOT NULL UNIQUE,
  email           VARCHAR(255) NOT NULL UNIQUE,
  password_hash   TEXT NOT NULL,
  activo          BOOLEAN NOT NULL DEFAULT true,
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Niveles de acceso. El catalogo es fijo y se carga aqui mismo.
CREATE TABLE roles (
  id           SERIAL PRIMARY KEY,
  nombre       VARCHAR(30) NOT NULL UNIQUE,
  descripcion  TEXT
);

INSERT INTO roles (nombre, descripcion)
VALUES
  ('estudiante',    'Crea y edita sus propias habitaciones'),
  ('administrador', 'Gestiona usuarios y consulta toda la auditoria');

-- Relacion muchos a muchos: un usuario puede tener varios roles y un rol
-- pertenece a muchos usuarios. La llave primaria compuesta impide
-- asignar dos veces el mismo rol.
CREATE TABLE usuario_roles (
  usuario_id   INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  rol_id       INTEGER NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
  asignado_en  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (usuario_id, rol_id)
);

-- Cada habitacion pasa a tener un dueno obligatorio. Las habitaciones que
-- ya existen (por ejemplo las de 03_seed.sql) se asignan a la cuenta
-- "sistema", que esta inactiva y cuyo hash es la firma bcrypt de un
-- secreto aleatorio descartado: no puede iniciar sesion. (Un hash que no
-- sea bcrypt, como '!', haria fallar crypt() con "invalid salt".)
-- Solo despues del relleno se exige NOT NULL.
INSERT INTO usuarios (nombre_usuario, email, password_hash, activo)
VALUES ('sistema', 'sistema@modelado3d.local',
        '$2a$10$EE9du9RvnKHXHEAghkxGGeH5zyKqwsCqq0IbZ18DA6n/cq.3LSqvS', false);

ALTER TABLE habitaciones ADD COLUMN usuario_id INTEGER;

UPDATE habitaciones
SET usuario_id = (SELECT id FROM usuarios WHERE nombre_usuario = 'sistema')
WHERE usuario_id IS NULL;

ALTER TABLE habitaciones
  ALTER COLUMN usuario_id SET NOT NULL,
  ADD CONSTRAINT fk_habitaciones_usuario
  FOREIGN KEY (usuario_id) REFERENCES usuarios(id) ON DELETE CASCADE;

CREATE INDEX idx_habitaciones_usuario
  ON habitaciones (usuario_id);

-- Sesiones abiertas desde el navegador. Se guarda el SHA-256 del token,
-- no el token: una fuga de esta tabla no permite suplantar sesiones.
CREATE TABLE sesiones (
  id          BIGSERIAL PRIMARY KEY,
  usuario_id  INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  token_hash  CHAR(64) NOT NULL UNIQUE,
  expira_en   TIMESTAMPTZ NOT NULL,
  revocada    BOOLEAN NOT NULL DEFAULT false,
  creado_en   TIMESTAMPTZ NOT NULL DEFAULT now()
);
