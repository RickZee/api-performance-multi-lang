-- Add filter targets and per-target approval/deployment tracking
-- This migration adds support for filters that can target multiple platforms (Flink, Spring Boot, or both)
-- with separate approval and deployment workflows per target.

-- Add targets column (JSONB array of target types: ["flink", "spring"])
ALTER TABLE filters ADD COLUMN IF NOT EXISTS targets JSONB DEFAULT '["flink", "spring"]'::jsonb;

-- Add per-target approval columns
ALTER TABLE filters ADD COLUMN IF NOT EXISTS approved_for_flink BOOLEAN DEFAULT false;
ALTER TABLE filters ADD COLUMN IF NOT EXISTS approved_for_spring BOOLEAN DEFAULT false;
ALTER TABLE filters ADD COLUMN IF NOT EXISTS approved_for_flink_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE filters ADD COLUMN IF NOT EXISTS approved_for_flink_by VARCHAR(255);
ALTER TABLE filters ADD COLUMN IF NOT EXISTS approved_for_spring_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE filters ADD COLUMN IF NOT EXISTS approved_for_spring_by VARCHAR(255);

-- Add per-target deployment status columns
ALTER TABLE filters ADD COLUMN IF NOT EXISTS deployed_to_flink BOOLEAN DEFAULT false;
ALTER TABLE filters ADD COLUMN IF NOT EXISTS deployed_to_flink_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE filters ADD COLUMN IF NOT EXISTS deployed_to_spring BOOLEAN DEFAULT false;
ALTER TABLE filters ADD COLUMN IF NOT EXISTS deployed_to_spring_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE filters ADD COLUMN IF NOT EXISTS flink_deployment_error TEXT;
ALTER TABLE filters ADD COLUMN IF NOT EXISTS spring_deployment_error TEXT;

-- Migrate existing data: set approval flags based on current status
-- If status is 'approved' or 'deployed', approve for both targets (backward compatibility)
UPDATE filters 
SET 
    approved_for_flink = CASE WHEN status IN ('approved', 'deployed') THEN true ELSE false END,
    approved_for_spring = CASE WHEN status IN ('approved', 'deployed') THEN true ELSE false END,
    approved_for_flink_at = CASE WHEN status IN ('approved', 'deployed') AND approved_at IS NOT NULL THEN approved_at ELSE NULL END,
    approved_for_flink_by = CASE WHEN status IN ('approved', 'deployed') THEN approved_by ELSE NULL END,
    approved_for_spring_at = CASE WHEN status IN ('approved', 'deployed') AND approved_at IS NOT NULL THEN approved_at ELSE NULL END,
    approved_for_spring_by = CASE WHEN status IN ('approved', 'deployed') THEN approved_by ELSE NULL END,
    deployed_to_flink = CASE WHEN status = 'deployed' AND deployed_at IS NOT NULL THEN true ELSE false END,
    deployed_to_flink_at = CASE WHEN status = 'deployed' THEN deployed_at ELSE NULL END,
    deployed_to_spring = false,
    flink_deployment_error = CASE WHEN status = 'failed' THEN deployment_error ELSE NULL END
WHERE targets IS NULL OR targets = '[]'::jsonb;

-- Create indexes for per-target queries
CREATE INDEX IF NOT EXISTS idx_filters_targets ON filters USING GIN (targets);
CREATE INDEX IF NOT EXISTS idx_filters_approved_for_flink ON filters(approved_for_flink);
CREATE INDEX IF NOT EXISTS idx_filters_approved_for_spring ON filters(approved_for_spring);
CREATE INDEX IF NOT EXISTS idx_filters_deployed_to_flink ON filters(deployed_to_flink);
CREATE INDEX IF NOT EXISTS idx_filters_deployed_to_spring ON filters(deployed_to_spring);

-- Add comments
COMMENT ON COLUMN filters.targets IS 'Array of deployment targets: ["flink", "spring"]';
COMMENT ON COLUMN filters.approved_for_flink IS 'Approval status for Flink deployment';
COMMENT ON COLUMN filters.approved_for_spring IS 'Approval status for Spring Boot deployment';
COMMENT ON COLUMN filters.deployed_to_flink IS 'Deployment status for Flink';
COMMENT ON COLUMN filters.deployed_to_spring IS 'Deployment status for Spring Boot';

