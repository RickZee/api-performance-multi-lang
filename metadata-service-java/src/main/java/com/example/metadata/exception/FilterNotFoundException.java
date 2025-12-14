package com.example.metadata.exception;

public class FilterNotFoundException extends RuntimeException {
    public FilterNotFoundException(String message) {
        super(message);
    }
    
    public FilterNotFoundException(String filterId, String version) {
        super(String.format("Filter with id '%s' not found in version '%s'", filterId, version));
    }
}
