-- Public profiles (migration 007): one profile per account, unique public codes, a visible name of 1 to
-- 40 characters or NULL (anonymous), an owner is required, and a new profile is anonymous unless a name
-- is given. Run on an empty database after schema.sql.
BEGIN;

DO $$
DECLARE
  profile_id integer;
  visible_name text;
BEGIN
  -- A profile inserted without a name is anonymous.
  INSERT INTO perfiles_publicos (user_id, codigo) VALUES ('1', 'AAAAAAAAAAAAAAAA')
  RETURNING id, nombre_visible INTO profile_id, visible_name;
  IF visible_name IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: test_public_profiles: a new profile is not anonymous';
  END IF;

  -- One profile per account.
  BEGIN
    INSERT INTO perfiles_publicos (user_id, codigo) VALUES ('1', 'BBBBBBBBBBBBBBBB');
    RAISE EXCEPTION 'FAIL: test_public_profiles: an account got two profiles';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  -- Public codes are unique.
  BEGIN
    INSERT INTO perfiles_publicos (user_id, codigo) VALUES ('2', 'AAAAAAAAAAAAAAAA');
    RAISE EXCEPTION 'FAIL: test_public_profiles: a repeated public code was accepted';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  -- 1 and 40 characters are accepted; 41 and the empty string are rejected; NULL is anonymous again.
  UPDATE perfiles_publicos SET nombre_visible = 'A' WHERE id = profile_id;
  UPDATE perfiles_publicos SET nombre_visible = repeat('a', 40) WHERE id = profile_id;
  BEGIN
    UPDATE perfiles_publicos SET nombre_visible = repeat('a', 41) WHERE id = profile_id;
    RAISE EXCEPTION 'FAIL: test_public_profiles: a visible name of 41 characters was accepted';
  EXCEPTION WHEN check_violation OR string_data_right_truncation THEN
    NULL;
  END;
  BEGIN
    UPDATE perfiles_publicos SET nombre_visible = '' WHERE id = profile_id;
    RAISE EXCEPTION 'FAIL: test_public_profiles: an empty visible name was accepted';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
  UPDATE perfiles_publicos SET nombre_visible = NULL WHERE id = profile_id;

  -- A profile always has an owner.
  BEGIN
    INSERT INTO perfiles_publicos (user_id, codigo) VALUES (NULL, 'CCCCCCCCCCCCCCCC');
    RAISE EXCEPTION 'FAIL: test_public_profiles: a profile without user_id was accepted';
  EXCEPTION WHEN not_null_violation THEN
    NULL;
  END;

  RAISE NOTICE 'PASS: test_public_profiles';
END
$$;

ROLLBACK;
