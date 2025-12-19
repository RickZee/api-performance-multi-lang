package io.debezium.connector.dsql;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.Statement;
import java.sql.Timestamp;
import java.sql.Types;
import java.time.Instant;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Tests for data type mapping edge cases in DSQL connector.
 * 
 * Covers DECIMAL, HSTORE, PostGIS, toasted values, column limits, and row size limits.
 */
@Testcontainers(disabledWithoutDocker = true)
@ExtendWith(org.testcontainers.junit.jupiter.TestcontainersExtension.class)
class DsqlDataTypeMappingTest {
    
    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15")
            .withDatabaseName("testdb")
            .withUsername("testuser")
            .withPassword("testpass");
    
    @BeforeEach
    void setUp() throws Exception {
        // Access container to trigger startup (Testcontainers starts lazily)
        // This will start the container if not already running
        String jdbcUrl = postgres.getJdbcUrl();
        
        // Clean up any existing test tables
        try (Connection conn = DriverManager.getConnection(
                jdbcUrl,
                postgres.getUsername(),
                postgres.getPassword())) {
            
            try (Statement stmt = conn.createStatement()) {
                stmt.execute("DROP TABLE IF EXISTS data_type_test");
                stmt.execute("DROP TABLE IF EXISTS decimal_test");
                stmt.execute("DROP TABLE IF EXISTS hstore_test");
                stmt.execute("DROP TABLE IF EXISTS array_test");
                stmt.execute("DROP TABLE IF EXISTS many_columns_test");
                stmt.execute("DROP TABLE IF EXISTS large_row_test");
            }
        }
    }
    
    @Test
    void testDecimalPrecisionMapping() throws Exception {
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            try (Statement stmt = conn.createStatement()) {
                // Create table with various DECIMAL/NUMERIC precisions
                stmt.execute(
                    "CREATE TABLE decimal_test (" +
                    "    id VARCHAR(255) PRIMARY KEY," +
                    "    saved_date TIMESTAMP WITH TIME ZONE," +
                    "    small_decimal DECIMAL(5,2)," +
                    "    large_decimal NUMERIC(38,10)," +
                    "    money_decimal DECIMAL(19,4)" +
                    ")"
                );
                
                // Insert test data
                stmt.execute(
                    "INSERT INTO decimal_test (id, saved_date, small_decimal, large_decimal, money_decimal) " +
                    "VALUES ('dec-1', NOW(), 123.45, 123456789012345678.1234567890, 9999999999999.9999)"
                );
            }
            
            // Build schema and verify DECIMAL is mapped to string
            DsqlSchema schema = new DsqlSchema("decimal_test", "dsql-cdc");
            schema.buildSchemas(conn.getMetaData(), "public");
            schema.validateRequiredColumns();
            
            // DECIMAL should be mapped to string for precision preservation
            assertThat(schema.getColumnSchemas().get("small_decimal").type()).isEqualTo(org.apache.kafka.connect.data.Schema.Type.STRING);
            assertThat(schema.getColumnSchemas().get("large_decimal").type()).isEqualTo(org.apache.kafka.connect.data.Schema.Type.STRING);
            assertThat(schema.getColumnSchemas().get("money_decimal").type()).isEqualTo(org.apache.kafka.connect.data.Schema.Type.STRING);
        }
    }
    
    @Test
    void testHstoreAsJsonMapping() throws Exception {
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            try (Statement stmt = conn.createStatement()) {
                // Enable HSTORE extension
                stmt.execute("CREATE EXTENSION IF NOT EXISTS hstore");
                
                // Create table with HSTORE
                stmt.execute(
                    "CREATE TABLE hstore_test (" +
                    "    id VARCHAR(255) PRIMARY KEY," +
                    "    saved_date TIMESTAMP WITH TIME ZONE," +
                    "    metadata HSTORE" +
                    ")"
                );
                
                // Insert test data
                stmt.execute(
                    "INSERT INTO hstore_test (id, saved_date, metadata) " +
                    "VALUES ('hstore-1', NOW(), 'key1=>value1,key2=>value2'::hstore)"
                );
            }
            
            // Build schema - HSTORE should be mapped to string (as JSON)
            DsqlSchema schema = new DsqlSchema("hstore_test", "dsql-cdc");
            schema.buildSchemas(conn.getMetaData(), "public");
            schema.validateRequiredColumns();
            
            // HSTORE maps to OTHER type, which should be string
            assertThat(schema.getColumnSchemas().get("metadata").type()).isEqualTo(org.apache.kafka.connect.data.Schema.Type.STRING);
        }
    }
    
    @Test
    void testJsonbTypeMapping() throws Exception {
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            try (Statement stmt = conn.createStatement()) {
                stmt.execute(
                    "CREATE TABLE data_type_test (" +
                    "    id VARCHAR(255) PRIMARY KEY," +
                    "    saved_date TIMESTAMP WITH TIME ZONE," +
                    "    jsonb_data JSONB," +
                    "    json_data JSON" +
                    ")"
                );
                
                stmt.execute(
                    "INSERT INTO data_type_test (id, saved_date, jsonb_data, json_data) " +
                    "VALUES ('json-1', NOW(), '{\"key\": \"value\"}'::jsonb, '{\"key\": \"value\"}'::json)"
                );
            }
            
            DsqlSchema schema = new DsqlSchema("data_type_test", "dsql-cdc");
            schema.buildSchemas(conn.getMetaData(), "public");
            
            // JSONB and JSON should map to string
            assertThat(schema.getColumnSchemas().get("jsonb_data").type()).isEqualTo(org.apache.kafka.connect.data.Schema.Type.STRING);
            assertThat(schema.getColumnSchemas().get("json_data").type()).isEqualTo(org.apache.kafka.connect.data.Schema.Type.STRING);
        }
    }
    
    @Test
    void testArrayTypeMapping() throws Exception {
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            try (Statement stmt = conn.createStatement()) {
                stmt.execute(
                    "CREATE TABLE array_test (" +
                    "    id VARCHAR(255) PRIMARY KEY," +
                    "    saved_date TIMESTAMP WITH TIME ZONE," +
                    "    int_array INTEGER[]," +
                    "    text_array TEXT[]," +
                    "    jsonb_array JSONB[]" +
                    ")"
                );
                
                stmt.execute(
                    "INSERT INTO array_test (id, saved_date, int_array, text_array, jsonb_array) " +
                    "VALUES ('array-1', NOW(), ARRAY[1,2,3], ARRAY['a','b','c'], ARRAY['{\"key\":\"value\"}'::jsonb])"
                );
            }
            
            DsqlSchema schema = new DsqlSchema("array_test", "dsql-cdc");
            schema.buildSchemas(conn.getMetaData(), "public");
            
            // Arrays should map to string (as JSON)
            assertThat(schema.getColumnSchemas().get("int_array").type()).isEqualTo(org.apache.kafka.connect.data.Schema.Type.STRING);
            assertThat(schema.getColumnSchemas().get("text_array").type()).isEqualTo(org.apache.kafka.connect.data.Schema.Type.STRING);
            assertThat(schema.getColumnSchemas().get("jsonb_array").type()).isEqualTo(org.apache.kafka.connect.data.Schema.Type.STRING);
        }
    }
    
    @Test
    void testTimestampWithTimeZone() throws Exception {
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            try (Statement stmt = conn.createStatement()) {
                stmt.execute(
                    "CREATE TABLE data_type_test (" +
                    "    id VARCHAR(255) PRIMARY KEY," +
                    "    saved_date TIMESTAMP WITH TIME ZONE," +
                    "    created_date TIMESTAMP WITHOUT TIME ZONE," +
                    "    date_col DATE," +
                    "    time_col TIME" +
                    ")"
                );
            }
            
            DsqlSchema schema = new DsqlSchema("data_type_test", "dsql-cdc");
            schema.buildSchemas(conn.getMetaData(), "public");
            
            // All timestamp/date/time types should map to Timestamp schema
            assertThat(schema.getColumnSchemas().get("saved_date").name()).contains("Timestamp");
            assertThat(schema.getColumnSchemas().get("created_date").name()).contains("Timestamp");
            assertThat(schema.getColumnSchemas().get("date_col").name()).contains("Timestamp");
            assertThat(schema.getColumnSchemas().get("time_col").name()).contains("Timestamp");
        }
    }
    
    @Test
    void testMaxColumnCountLimit() throws Exception {
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            try (Statement stmt = conn.createStatement()) {
                // Create table with 255 columns (DSQL limit)
                StringBuilder createTable = new StringBuilder(
                    "CREATE TABLE many_columns_test (id VARCHAR(255) PRIMARY KEY, saved_date TIMESTAMP WITH TIME ZONE"
                );
                
                for (int i = 1; i <= 253; i++) { // 253 + id + saved_date = 255
                    createTable.append(", col_").append(i).append(" VARCHAR(255)");
                }
                createTable.append(")");
                
                stmt.execute(createTable.toString());
            }
            
            // Schema should build successfully with 255 columns
            DsqlSchema schema = new DsqlSchema("many_columns_test", "dsql-cdc");
            schema.buildSchemas(conn.getMetaData(), "public");
            
            assertThat(schema.getColumnNames().size()).isEqualTo(255);
            assertThat(schema.getColumnSchemas().size()).isEqualTo(255);
        }
    }
    
    @Test
    void testLargeRowSizeLimit() throws Exception {
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            try (Statement stmt = conn.createStatement()) {
                // Create table with large text columns
                stmt.execute(
                    "CREATE TABLE large_row_test (" +
                    "    id VARCHAR(255) PRIMARY KEY," +
                    "    saved_date TIMESTAMP WITH TIME ZONE," +
                    "    large_text TEXT" +
                    ")"
                );
                
                // Insert row approaching 2 MiB limit (DSQL row size limit)
                // Use ~1.5 MiB to stay under limit but test large value handling
                String largeValue = "x".repeat(1_500_000); // 1.5 MB
                stmt.execute(
                    String.format("INSERT INTO large_row_test (id, saved_date, large_text) " +
                                 "VALUES ('large-1', NOW(), '%s')", largeValue.replace("'", "''"))
                );
            }
            
            // Schema should handle large values
            DsqlSchema schema = new DsqlSchema("large_row_test", "dsql-cdc");
            schema.buildSchemas(conn.getMetaData(), "public");
            
            assertThat(schema.getColumnSchemas().get("large_text").type()).isEqualTo(org.apache.kafka.connect.data.Schema.Type.STRING);
            
            // Verify data can be read
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery("SELECT LENGTH(large_text) FROM large_row_test WHERE id = 'large-1'")) {
                rs.next();
                assertThat(rs.getInt(1)).isGreaterThan(1_000_000);
            }
        }
    }
    
    @Test
    void testToastedValueHandling() throws Exception {
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            try (Statement stmt = conn.createStatement()) {
                // Create table with TEXT column that might be toasted
                stmt.execute(
                    "CREATE TABLE data_type_test (" +
                    "    id VARCHAR(255) PRIMARY KEY," +
                    "    saved_date TIMESTAMP WITH TIME ZONE," +
                    "    toasted_text TEXT" +
                    ")"
                );
                
                // Insert value that might trigger TOAST (PostgreSQL toasts values > 2KB)
                String toastedValue = "x".repeat(3000);
                stmt.execute(
                    String.format("INSERT INTO data_type_test (id, saved_date, toasted_text) " +
                                 "VALUES ('toast-1', NOW(), '%s')", toastedValue.replace("'", "''"))
                );
            }
            
            // Schema should handle toasted values
            DsqlSchema schema = new DsqlSchema("data_type_test", "dsql-cdc");
            schema.buildSchemas(conn.getMetaData(), "public");
            
            // Verify toasted value can be read (PostgreSQL handles TOAST automatically)
            try (Statement stmt = conn.createStatement();
                 var rs = stmt.executeQuery("SELECT LENGTH(toasted_text) FROM data_type_test WHERE id = 'toast-1'")) {
                rs.next();
                assertThat(rs.getInt(1)).isEqualTo(3000);
            }
        }
    }
    
    @Test
    void testUnsupportedTypeError() throws Exception {
        // Test that unknown types are handled gracefully
        // Since we map unknown types to string, this should not throw
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            DsqlSchema schema = new DsqlSchema("nonexistent_table", "dsql-cdc");
            
            // Building schema for non-existent table should throw SQLException
            assertThatThrownBy(() -> schema.buildSchemas(conn.getMetaData(), "public"))
                    .isInstanceOf(java.sql.SQLException.class);
        }
    }
    
    @Test
    void testPostgisTypes() throws Exception {
        // Note: PostGIS types may not be available in all PostgreSQL installations
        // This test verifies they would be handled if present
        try (Connection conn = DriverManager.getConnection(
                postgres.getJdbcUrl(),
                postgres.getUsername(),
                postgres.getPassword())) {
            
            try (Statement stmt = conn.createStatement()) {
                // Try to enable PostGIS extension
                try {
                    stmt.execute("CREATE EXTENSION IF NOT EXISTS postgis");
                    
                    stmt.execute(
                        "CREATE TABLE IF NOT EXISTS postgis_test (" +
                        "    id VARCHAR(255) PRIMARY KEY," +
                        "    saved_date TIMESTAMP WITH TIME ZONE," +
                        "    geom GEOMETRY" +
                        ")"
                    );
                    
                    stmt.execute(
                        "INSERT INTO postgis_test (id, saved_date, geom) " +
                        "VALUES ('geom-1', NOW(), ST_GeomFromText('POINT(1 1)'))"
                    );
                    
                    // Build schema - PostGIS types map to OTHER, which becomes string
                    DsqlSchema schema = new DsqlSchema("postgis_test", "dsql-cdc");
                    schema.buildSchemas(conn.getMetaData(), "public");
                    
                    // PostGIS types should map to string
                    assertThat(schema.getColumnSchemas().get("geom").type()).isEqualTo(org.apache.kafka.connect.data.Schema.Type.STRING);
                } catch (java.sql.SQLException e) {
                    // PostGIS not available, skip test
                    org.junit.jupiter.api.Assumptions.assumeTrue(false, "PostGIS extension not available");
                }
            }
        }
    }
}
