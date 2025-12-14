package com.example.metadata.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ValidationResponse {
    @JsonProperty("valid")
    private boolean valid;
    
    @JsonProperty("errors")
    private List<ValidationError> errors;
    
    @JsonProperty("version")
    private String version;
    
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class ValidationError {
        @JsonProperty("field")
        private String field;
        
        @JsonProperty("message")
        private String message;
    }
}
