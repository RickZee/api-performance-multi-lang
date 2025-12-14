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
public class GenerateSQLResponse {
    @JsonProperty("filterId")
    private String filterId;
    
    @JsonProperty("sql")
    private String sql;
    
    @JsonProperty("statements")
    private List<String> statements;
    
    @JsonProperty("valid")
    private boolean valid;
    
    @JsonProperty("validationErrors")
    private List<String> validationErrors;
}
