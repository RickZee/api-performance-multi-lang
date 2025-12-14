package com.example.metadata.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;
import java.util.List;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FilterStatusResponse {
    @JsonProperty("filterId")
    private String filterId;
    
    @JsonProperty("status")
    private String status;
    
    @JsonProperty("flinkStatementIds")
    private List<String> flinkStatementIds;
    
    @JsonProperty("deployedAt")
    private Instant deployedAt;
    
    @JsonProperty("deploymentError")
    private String deploymentError;
    
    @JsonProperty("lastChecked")
    private Instant lastChecked;
}
