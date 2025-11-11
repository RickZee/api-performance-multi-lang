-- Initialize PostgreSQL database for car entities with hybrid relational schema
-- This script runs when the PostgreSQL container starts for the first time

-- Create the car_entities table (main entity with extracted fields from entity section)
CREATE TABLE IF NOT EXISTS car_entities (
    id VARCHAR(255) PRIMARY KEY,  -- entityId from entity section
    entity_type VARCHAR(100) NOT NULL,   -- entityType from entity section
    created_at TIMESTAMP WITH TIME ZONE,  -- createdAt from entity section
    updated_at TIMESTAMP WITH TIME ZONE,  -- updatedAt from entity section
    data JSONB NOT NULL  -- rest of the car data as JSON
);

-- Create the loan_entities table (separate entity with extracted fields from entity section)
CREATE TABLE IF NOT EXISTS loan_entities (
    id VARCHAR(255) PRIMARY KEY,  -- id from loan object
    car_id VARCHAR(255) NOT NULL REFERENCES car_entities(id) ON DELETE CASCADE,  -- FK to car_entities
    entity_type VARCHAR(100) NOT NULL DEFAULT 'Loan',  -- entityType (will be 'Loan')
    created_at TIMESTAMP WITH TIME ZONE,  -- createdAt from loan object
    updated_at TIMESTAMP WITH TIME ZONE,  -- updatedAt from loan object
    data JSONB NOT NULL  -- rest of the loan data as JSON
);

-- Create the service_record_entities table (separate entity)
CREATE TABLE IF NOT EXISTS service_record_entities (
    id SERIAL PRIMARY KEY,  -- auto-generated ID
    car_id VARCHAR(255) NOT NULL REFERENCES car_entities(id) ON DELETE CASCADE,  -- FK to car_entities
    entity_type VARCHAR(100) NOT NULL DEFAULT 'ServiceRecord',  -- entityType
    created_at TIMESTAMP WITH TIME ZONE,  -- createdAt from service record
    updated_at TIMESTAMP WITH TIME ZONE,  -- updatedAt from service record
    data JSONB NOT NULL  -- rest of the service record data as JSON
);

-- Create the loan_payment_entities table (separate entity with extracted fields from entity section)
CREATE TABLE IF NOT EXISTS loan_payment_entities (
    id VARCHAR(255) PRIMARY KEY,  -- id from loan payment object
    loan_id VARCHAR(255) NOT NULL REFERENCES loan_entities(id) ON DELETE CASCADE,  -- FK to loan_entities
    entity_type VARCHAR(100) NOT NULL DEFAULT 'LoanPayment',  -- entityType (will be 'LoanPayment')
    created_at TIMESTAMP WITH TIME ZONE,  -- createdAt from loan payment object
    updated_at TIMESTAMP WITH TIME ZONE,  -- updatedAt from loan payment object
    data JSONB NOT NULL  -- rest of the loan payment data as JSON
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_car_entities_entity_type ON car_entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_car_entities_created_at ON car_entities(created_at);
CREATE INDEX IF NOT EXISTS idx_car_entities_data_gin ON car_entities USING GIN (data);

CREATE INDEX IF NOT EXISTS idx_loan_entities_car_id ON loan_entities(car_id);
CREATE INDEX IF NOT EXISTS idx_loan_entities_entity_type ON loan_entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_loan_entities_created_at ON loan_entities(created_at);
CREATE INDEX IF NOT EXISTS idx_loan_entities_data_gin ON loan_entities USING GIN (data);

CREATE INDEX IF NOT EXISTS idx_service_record_entities_car_id ON service_record_entities(car_id);
CREATE INDEX IF NOT EXISTS idx_service_record_entities_entity_type ON service_record_entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_service_record_entities_created_at ON service_record_entities(created_at);
CREATE INDEX IF NOT EXISTS idx_service_record_entities_data_gin ON service_record_entities USING GIN (data);

CREATE INDEX IF NOT EXISTS idx_loan_payment_entities_loan_id ON loan_payment_entities(loan_id);
CREATE INDEX IF NOT EXISTS idx_loan_payment_entities_entity_type ON loan_payment_entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_loan_payment_entities_created_at ON loan_payment_entities(created_at);
CREATE INDEX IF NOT EXISTS idx_loan_payment_entities_data_gin ON loan_payment_entities USING GIN (data);

-- Grant permissions
GRANT ALL PRIVILEGES ON TABLE car_entities TO postgres;
GRANT ALL PRIVILEGES ON TABLE loan_entities TO postgres;
GRANT ALL PRIVILEGES ON TABLE service_record_entities TO postgres;
GRANT ALL PRIVILEGES ON TABLE loan_payment_entities TO postgres;
GRANT USAGE, SELECT ON SEQUENCE service_record_entities_id_seq TO postgres;

-- Log initialization
DO $$
BEGIN
    RAISE NOTICE 'Car entities database with hybrid relational schema initialized successfully';
END $$;
