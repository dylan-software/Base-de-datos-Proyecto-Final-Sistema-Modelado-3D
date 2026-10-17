-- An email can only be registered once (ix_usuarios_email). Run on an empty database after schema.sql.
BEGIN;

DO $$
BEGIN
  INSERT INTO usuarios (nombre, email, password_hash) VALUES ('Ana', 'ana@example.com', 'scrypt$00$00');
  BEGIN
    INSERT INTO usuarios (nombre, email, password_hash) VALUES ('Otra Ana', 'ana@example.com', 'scrypt$11$11');
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'PASS: test_usuarios_email_unique';
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL: test_usuarios_email_unique: a second account with the same email was accepted';
END
$$;

ROLLBACK;
