-- Seguridad y control de accesos. Ejecutar despues de 03_seed.sql.
-- Modela usuarios, roles y la relacion de cada habitacion con su dueno.

-- TODO: definiciones de tablas de seguridad.

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
