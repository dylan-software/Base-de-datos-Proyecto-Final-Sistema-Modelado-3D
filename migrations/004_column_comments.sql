-- Migration 004: column documentation, visible in the Supabase Table Editor.
--
-- Same comments as schema.sql. Units differ between tables: muebles_catalogo is in CENTIMETERS,
-- habitaciones and muebles_sugeridos are in METERS. Apply after 001 and 002, which add columns
-- documented here. COMMENT ON replaces any previous comment, so running it again is a no-op.

BEGIN;

COMMENT ON TABLE usuarios IS 'Accounts of the web app. The backend issues HS256 session tokens whose sub is usuarios.id.';
COMMENT ON COLUMN usuarios.nombre IS 'Display name entered at registration.';
COMMENT ON COLUMN usuarios.email IS 'Login email, stored trimmed and lowercased by the backend; unique.';
COMMENT ON COLUMN usuarios.password_hash IS 'scrypt$<salt hex>$<hash hex> (n = 2^14, r = 8, p = 1). Never the plain password.';

COMMENT ON TABLE categorias IS 'Furniture categories, shared by every account.';
COMMENT ON COLUMN categorias.nombre IS 'Category name as first typed; unique ignoring case (uq_categorias_nombre_lower).';

COMMENT ON TABLE muebles_catalogo IS 'Furniture each account adds to its own catalog. Sizes in CENTIMETERS.';
COMMENT ON COLUMN muebles_catalogo.user_id IS 'Owning account: the session token sub (usuarios.id as text).';
COMMENT ON COLUMN muebles_catalogo.categoria_id IS 'Category of the item (categorias.id).';
COMMENT ON COLUMN muebles_catalogo.nombre IS 'Item name, checked by the backend to be a plausible piece of furniture.';
COMMENT ON COLUMN muebles_catalogo.ancho IS 'Width in CENTIMETERS, as typed in the web form (rooms use meters).';
COMMENT ON COLUMN muebles_catalogo.alto IS 'Height in CENTIMETERS.';
COMMENT ON COLUMN muebles_catalogo.profundidad IS 'Depth in CENTIMETERS.';

COMMENT ON TABLE habitaciones IS 'Rooms. Meters; the 3D y axis points up, the floor is the x/z plane.';
COMMENT ON COLUMN habitaciones.user_id IS 'Owning account: the session token sub (usuarios.id as text).';
COMMENT ON COLUMN habitaciones.nombre IS 'Room name.';
COMMENT ON COLUMN habitaciones.ancho IS 'Extent along x in meters; the bounding box of vertices when they are set.';
COMMENT ON COLUMN habitaciones.alto IS 'Ceiling height in meters (3D y axis).';
COMMENT ON COLUMN habitaciones.profundidad IS 'Extent along z in meters; the bounding box of vertices when they are set.';
COMMENT ON COLUMN habitaciones.vertices IS 'Floor polygon as [{"x": m, "y": m}, ...]; the polygon y is the 3D z axis. NULL means the rectangle [0, ancho] x [0, profundidad].';

COMMENT ON TABLE muebles_sugeridos IS 'Furniture placed in a room by the AI proposal or the generated layout. Meters.';
COMMENT ON COLUMN muebles_sugeridos.habitacion_id IS 'Room the piece is placed in (habitaciones.id); deleted with the room.';
COMMENT ON COLUMN muebles_sugeridos.nombre IS 'Name of the placed piece.';
COMMENT ON COLUMN muebles_sugeridos.ancho IS 'Width along x in meters.';
COMMENT ON COLUMN muebles_sugeridos.alto IS 'Height in meters.';
COMMENT ON COLUMN muebles_sugeridos.profundidad IS 'Depth along z in meters.';
COMMENT ON COLUMN muebles_sugeridos.posicion_x IS 'Center of the footprint along x, in meters.';
COMMENT ON COLUMN muebles_sugeridos.posicion_y IS 'Height of the base above the floor, in meters (0 = on the floor).';
COMMENT ON COLUMN muebles_sugeridos.posicion_z IS 'Center of the footprint along z, in meters.';

COMMIT;
