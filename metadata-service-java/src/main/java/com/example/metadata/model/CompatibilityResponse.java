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
public class CompatibilityResponse {
    @JsonProperty("compatible")
    private boolean compatible;
    
    @JsonProperty("reason")
    private String reason;
    
    @JsonProperty("breakingChanges")
    private List<String> breakingChanges;
    
    @JsonProperty("nonBreakingChanges")
    private List<String> nonBreakingChanges;
    
    @JsonProperty("oldVersion")
    private String oldVersion;
    
    @JsonProperty("newVersion")
    private String newVersion;
}

