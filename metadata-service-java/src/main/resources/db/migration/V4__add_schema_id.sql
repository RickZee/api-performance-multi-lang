-- Add schema_id column to filters table
-- schema_id is a unique identifier for the schema, while schema_version is the version string (e.g., "v1", "v2")

-- First add as nullable for existing data
ALTER TABLE filters ADD COLUMN IF NOT EXISTS schema_id VARCHAR(255);

-- Set a default value for existing rows (using schema_version as default)
UPDATE filters SET schema_id = schema_version WHERE schema_id IS NULL;

-- Now make it NOT NULL
ALTER TABLE filters ALTER COLUMN schema_id SET NOT NULL;

-- Create index for schema_id queries
CREATE INDEX IF NOT EXISTS idx_filters_schema_id ON filters(schema_id);

-- Create composite index for schema_id and schema_version
CREATE INDEX IF NOT EXISTS idx_filters_schema_id_version ON filters(schema_id, schema_version);

-- Add comment
COMMENT ON COLUMN filters.schema_id IS 'Unique identifier for the schema (e.g., UUID or unique name)';

