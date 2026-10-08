-- Run this in the Supabase SQL editor AFTER schema.sql, to confirm it worked.

-- 1) Extensions: expect 2 rows (postgis, vector)
SELECT extname FROM pg_extension WHERE extname IN ('postgis', 'vector') ORDER BY extname;

-- 2) Tables: expect 4 rows (furniture, placed_items, projects, spaces)
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' AND table_name IN ('furniture', 'projects', 'spaces', 'placed_items')
ORDER BY table_name;

-- 3) Indexes: expect 3 rows (idx_furniture_style_embedding, idx_placed_items_project, idx_spaces_shape)
SELECT indexname FROM pg_indexes WHERE schemaname = 'public' AND indexname LIKE 'idx_%' ORDER BY indexname;

-- 4) Row Level Security: expect 4 rows, all with relrowsecurity = true
SELECT relname, relrowsecurity FROM pg_class
WHERE relname IN ('furniture', 'projects', 'spaces', 'placed_items') AND relkind = 'r'
ORDER BY relname;
