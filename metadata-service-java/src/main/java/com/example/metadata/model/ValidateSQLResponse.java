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
public class ValidateSQLResponse {
    @JsonProperty("valid")
    private boolean valid;
    
    @JsonProperty("errors")
    private List<String> errors;
    
    @JsonProperty("warnings")
    private List<String> warnings;
}
