-- Refactor filter structure:
-- 1. Rename consumer_id to consumer_group
-- 2. Move condition_logic into conditions JSONB (change from array to object with logic and conditions fields)
-- 3. Add spring_filter_id column to track Spring YAML filter deployment

-- Step 1: Rename consumer_id to consumer_group
ALTER TABLE filters RENAME COLUMN consumer_id TO consumer_group;

-- Step 2: Migrate condition_logic into conditions JSONB
-- First, update the structure: change conditions from array to object with logic and conditions fields
-- For existing data, wrap the array in an object with logic from condition_logic column
UPDATE filters
SET conditions = jsonb_build_object(
    'logic', COALESCE(condition_logic, 'AND'),
    'conditions', COALESCE(conditions::jsonb, '[]'::jsonb)
)
WHERE conditions::text NOT LIKE '{%' OR conditions::text LIKE '{%"logic"%}';

-- Step 3: Add spring_filter_id column (similar to flink_statement_ids but for Spring YAML)
ALTER TABLE filters ADD COLUMN IF NOT EXISTS spring_filter_id VARCHAR(255);

-- Step 4: Remove condition_logic column (after migration)
-- Note: We'll keep it for now during transition, but mark it as deprecated
-- ALTER TABLE filters DROP COLUMN condition_logic;

-- Update indexes
CREATE INDEX IF NOT EXISTS idx_filters_consumer_group ON filters(consumer_group);
DROP INDEX IF EXISTS idx_filters_consumer_id;

-- Add comments
COMMENT ON COLUMN filters.consumer_group IS 'Consumer group identifier for the filter';
COMMENT ON COLUMN filters.conditions IS 'JSONB object with logic (AND/OR) and conditions array';
COMMENT ON COLUMN filters.spring_filter_id IS 'Spring YAML filter identifier for tracking deployment';

