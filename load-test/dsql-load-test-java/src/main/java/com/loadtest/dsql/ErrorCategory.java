package com.loadtest.dsql;

/**
 * Error categories for tracking different types of failures.
 */
public enum ErrorCategory {
    CONNECTION_TIMEOUT("Connection timeout or pool exhaustion"),
    QUERY_ERROR("SQL query execution error"),
    AUTH_ERROR("Authentication or token refresh error"),
    NETWORK_ERROR("Network connectivity error"),
    UNKNOWN_ERROR("Unknown or unclassified error");
    
    private final String description;
    
    ErrorCategory(String description) {
        this.description = description;
    }
    
    public String getDescription() {
        return description;
    }
    
    /**
     * Categorize an exception into an error category.
     */
    public static ErrorCategory categorize(Exception e) {
        if (e == null) {
            return UNKNOWN_ERROR;
        }
        
        String message = e.getMessage();
        String className = e.getClass().getName();
        
        // Connection timeout errors
        if (message != null && (message.contains("timeout") || 
                               message.contains("Connection is not available") ||
                               message.contains("Connection pool"))) {
            return CONNECTION_TIMEOUT;
        }
        
        // SQL errors
        if (className.contains("SQLException") || className.contains("SQL")) {
            if (message != null && (message.contains("authentication") || 
                                   message.contains("token") ||
                                   message.contains("IAM"))) {
                return AUTH_ERROR;
            }
            return QUERY_ERROR;
        }
        
        // Network errors
        if (className.contains("Socket") || 
            className.contains("Network") ||
            className.contains("ConnectException") ||
            (message != null && message.contains("network"))) {
            return NETWORK_ERROR;
        }
        
        // Authentication errors
        if (message != null && (message.contains("authentication") || 
                               message.contains("unauthorized") ||
                               message.contains("token expired"))) {
            return AUTH_ERROR;
        }
        
        return UNKNOWN_ERROR;
    }
}

