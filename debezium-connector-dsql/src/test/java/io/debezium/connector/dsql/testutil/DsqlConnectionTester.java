package io.debezium.connector.dsql.testutil;

import io.debezium.connector.dsql.auth.IamTokenGenerator;
import io.debezium.connector.dsql.connection.DsqlConnectionPool;
import io.debezium.connector.dsql.connection.MultiRegionEndpoint;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;

/**
 * Utility class to test and validate real DSQL connections.
 * 
 * Reads configuration from environment variables and provides
 * methods to test IAM authentication, database connectivity,
 * and schema validation.
 */
public class DsqlConnectionTester {
    private static final Logger LOGGER = LoggerFactory.getLogger(DsqlConnectionTester.class);
    
    private final String primaryEndpoint;
    private final String secondaryEndpoint;
    private final int port;
    private final String databaseName;
    private final String region;
    private final String iamUsername;
    private final String[] tables;
    
    /**
     * Create a connection tester from environment variables.
     * 
     * @throws IllegalStateException if required environment variables are missing
     */
    public static DsqlConnectionTester fromEnvironment() {
        String primaryEndpoint = System.getenv("DSQL_ENDPOINT_PRIMARY");
        String secondaryEndpoint = System.getenv("DSQL_ENDPOINT_SECONDARY");
        String portStr = System.getenv("DSQL_PORT");
        String databaseName = System.getenv("DSQL_DATABASE_NAME");
        String region = System.getenv("DSQL_REGION");
        String iamUsername = System.getenv("DSQL_IAM_USERNAME");
        String tablesStr = System.getenv("DSQL_TABLES");
        
        // Validate required variables
        List<String> missing = new ArrayList<>();
        if (primaryEndpoint == null || primaryEndpoint.isEmpty()) {
            missing.add("DSQL_ENDPOINT_PRIMARY");
        }
        if (databaseName == null || databaseName.isEmpty()) {
            missing.add("DSQL_DATABASE_NAME");
        }
        if (region == null || region.isEmpty()) {
            missing.add("DSQL_REGION");
        }
        if (iamUsername == null || iamUsername.isEmpty()) {
            missing.add("DSQL_IAM_USERNAME");
        }
        if (tablesStr == null || tablesStr.isEmpty()) {
            missing.add("DSQL_TABLES");
        }
        
        if (!missing.isEmpty()) {
            throw new IllegalStateException(
                "Missing required environment variables: " + String.join(", ", missing) +
                ". Please set these variables or source .env.dsql file."
            );
        }
        
        int port = 5432;
        if (portStr != null && !portStr.isEmpty()) {
            try {
                port = Integer.parseInt(portStr);
            } catch (NumberFormatException e) {
                LOGGER.warn("Invalid DSQL_PORT value: {}, using default 5432", portStr);
            }
        }
        
        String[] tables = tablesStr.split(",");
        for (int i = 0; i < tables.length; i++) {
            tables[i] = tables[i].trim();
        }
        
        return new DsqlConnectionTester(
            primaryEndpoint,
            secondaryEndpoint,
            port,
            databaseName,
            region,
            iamUsername,
            tables
        );
    }
    
    private DsqlConnectionTester(String primaryEndpoint, String secondaryEndpoint, int port,
                                String databaseName, String region, String iamUsername, String[] tables) {
        this.primaryEndpoint = primaryEndpoint;
        this.secondaryEndpoint = secondaryEndpoint;
        this.port = port;
        this.databaseName = databaseName;
        this.region = region;
        this.iamUsername = iamUsername;
        this.tables = tables;
    }
    
    /**
     * Test IAM token generation.
     * 
     * @return true if token generation succeeds
     * @throws Exception if token generation fails
     */
    public boolean testIamTokenGeneration() throws Exception {
        LOGGER.info("Testing IAM token generation for endpoint: {}", primaryEndpoint);
        
        IamTokenGenerator tokenGenerator = new IamTokenGenerator(
            primaryEndpoint, port, iamUsername, region
        );
        
        try {
            String token = tokenGenerator.getToken();
            if (token == null || token.isEmpty()) {
                throw new Exception("Generated token is null or empty");
            }
            
            LOGGER.info("✓ IAM token generated successfully (length: {})", token.length());
            return true;
        } finally {
            tokenGenerator.close();
        }
    }
    
    /**
     * Test database connection using IAM authentication.
     * 
     * @return true if connection succeeds
     * @throws Exception if connection fails
     */
    public boolean testDatabaseConnection() throws Exception {
        LOGGER.info("Testing database connection to: {}:{}", primaryEndpoint, port);
        
        IamTokenGenerator tokenGenerator = new IamTokenGenerator(
            primaryEndpoint, port, iamUsername, region
        );
        
        try {
            String token = tokenGenerator.getToken();
            String jdbcUrl = String.format(
                "jdbc:postgresql://%s:%d/%s?user=%s&password=%s&sslmode=require",
                primaryEndpoint, port, databaseName, iamUsername, token
            );
            
            try (Connection conn = DriverManager.getConnection(jdbcUrl)) {
                try (Statement stmt = conn.createStatement();
                     ResultSet rs = stmt.executeQuery("SELECT version()")) {
                    if (rs.next()) {
                        String version = rs.getString(1);
                        LOGGER.info("✓ Database connection successful");
                        LOGGER.debug("Database version: {}", version);
                        return true;
                    } else {
                        throw new Exception("No result from version() query");
                    }
                }
            }
        } finally {
            tokenGenerator.close();
        }
    }
    
    /**
     * Validate that required tables exist and have required columns.
     * 
     * @return Validation result with details
     * @throws Exception if validation fails
     */
    public ValidationResult validateTables() throws Exception {
        LOGGER.info("Validating tables: {}", String.join(", ", tables));
        
        IamTokenGenerator tokenGenerator = new IamTokenGenerator(
            primaryEndpoint, port, iamUsername, region
        );
        
        ValidationResult result = new ValidationResult();
        
        try {
            String token = tokenGenerator.getToken();
            String jdbcUrl = String.format(
                "jdbc:postgresql://%s:%d/%s?user=%s&password=%s&sslmode=require",
                primaryEndpoint, port, databaseName, iamUsername, token
            );
            
            try (Connection conn = DriverManager.getConnection(jdbcUrl)) {
                DatabaseMetaData metaData = conn.getMetaData();
                
                for (String tableName : tables) {
                    TableValidation tableValidation = validateTable(metaData, tableName);
                    result.addTableValidation(tableValidation);
                }
            }
        } finally {
            tokenGenerator.close();
        }
        
        return result;
    }
    
    private TableValidation validateTable(DatabaseMetaData metaData, String tableName) throws SQLException {
        TableValidation validation = new TableValidation(tableName);
        
        // Check if table exists
        try (ResultSet tables = metaData.getTables(null, "public", tableName, new String[]{"TABLE"})) {
            if (!tables.next()) {
                validation.addError("Table does not exist");
                return validation;
            }
        }
        validation.setExists(true);
        
        // Check for saved_date column
        boolean hasSavedDate = false;
        boolean hasPrimaryKey = false;
        String primaryKeyColumn = null;
        
        try (ResultSet columns = metaData.getColumns(null, "public", tableName, null)) {
            while (columns.next()) {
                String columnName = columns.getString("COLUMN_NAME");
                if ("saved_date".equalsIgnoreCase(columnName)) {
                    hasSavedDate = true;
                    validation.setHasSavedDate(true);
                }
            }
        }
        
        // Check for primary key
        try (ResultSet pkColumns = metaData.getPrimaryKeys(null, "public", tableName)) {
            if (pkColumns.next()) {
                hasPrimaryKey = true;
                primaryKeyColumn = pkColumns.getString("COLUMN_NAME");
                validation.setHasPrimaryKey(true);
                validation.setPrimaryKeyColumn(primaryKeyColumn);
            }
        }
        
        if (!hasSavedDate) {
            validation.addError("Missing required column: saved_date");
        }
        
        if (!hasPrimaryKey) {
            validation.addError("Missing primary key");
        }
        
        if (hasSavedDate && hasPrimaryKey) {
            validation.setValid(true);
        }
        
        return validation;
    }
    
    /**
     * Run all connection tests and return a summary.
     */
    public TestSummary runAllTests() {
        TestSummary summary = new TestSummary();
        
        try {
            summary.setIamTokenTest(testIamTokenGeneration());
        } catch (Exception e) {
            summary.setIamTokenError(e.getMessage());
            LOGGER.error("IAM token generation test failed", e);
        }
        
        try {
            summary.setConnectionTest(testDatabaseConnection());
        } catch (Exception e) {
            summary.setConnectionError(e.getMessage());
            LOGGER.error("Database connection test failed", e);
        }
        
        try {
            summary.setValidationResult(validateTables());
        } catch (Exception e) {
            summary.setValidationError(e.getMessage());
            LOGGER.error("Table validation failed", e);
        }
        
        return summary;
    }
    
    // Inner classes for results
    
    public static class TestSummary {
        private Boolean iamTokenTest;
        private String iamTokenError;
        private Boolean connectionTest;
        private String connectionError;
        private ValidationResult validationResult;
        private String validationError;
        
        public boolean allTestsPassed() {
            return Boolean.TRUE.equals(iamTokenTest) &&
                   Boolean.TRUE.equals(connectionTest) &&
                   validationResult != null &&
                   validationResult.allTablesValid();
        }
        
        // Getters and setters
        public Boolean getIamTokenTest() { return iamTokenTest; }
        public void setIamTokenTest(Boolean iamTokenTest) { this.iamTokenTest = iamTokenTest; }
        public String getIamTokenError() { return iamTokenError; }
        public void setIamTokenError(String iamTokenError) { this.iamTokenError = iamTokenError; }
        public Boolean getConnectionTest() { return connectionTest; }
        public void setConnectionTest(Boolean connectionTest) { this.connectionTest = connectionTest; }
        public String getConnectionError() { return connectionError; }
        public void setConnectionError(String connectionError) { this.connectionError = connectionError; }
        public ValidationResult getValidationResult() { return validationResult; }
        public void setValidationResult(ValidationResult validationResult) { this.validationResult = validationResult; }
        public String getValidationError() { return validationError; }
        public void setValidationError(String validationError) { this.validationError = validationError; }
    }
    
    public static class ValidationResult {
        private final List<TableValidation> tableValidations = new ArrayList<>();
        
        public void addTableValidation(TableValidation validation) {
            tableValidations.add(validation);
        }
        
        public boolean allTablesValid() {
            return tableValidations.stream().allMatch(TableValidation::isValid);
        }
        
        public List<TableValidation> getTableValidations() {
            return tableValidations;
        }
    }
    
    public static class TableValidation {
        private final String tableName;
        private boolean exists;
        private boolean hasSavedDate;
        private boolean hasPrimaryKey;
        private String primaryKeyColumn;
        private boolean valid;
        private final List<String> errors = new ArrayList<>();
        
        public TableValidation(String tableName) {
            this.tableName = tableName;
        }
        
        public void addError(String error) {
            errors.add(error);
        }
        
        // Getters and setters
        public String getTableName() { return tableName; }
        public boolean isExists() { return exists; }
        public void setExists(boolean exists) { this.exists = exists; }
        public boolean isHasSavedDate() { return hasSavedDate; }
        public void setHasSavedDate(boolean hasSavedDate) { this.hasSavedDate = hasSavedDate; }
        public boolean isHasPrimaryKey() { return hasPrimaryKey; }
        public void setHasPrimaryKey(boolean hasPrimaryKey) { this.hasPrimaryKey = hasPrimaryKey; }
        public String getPrimaryKeyColumn() { return primaryKeyColumn; }
        public void setPrimaryKeyColumn(String primaryKeyColumn) { this.primaryKeyColumn = primaryKeyColumn; }
        public boolean isValid() { return valid; }
        public void setValid(boolean valid) { this.valid = valid; }
        public List<String> getErrors() { return errors; }
    }
}
