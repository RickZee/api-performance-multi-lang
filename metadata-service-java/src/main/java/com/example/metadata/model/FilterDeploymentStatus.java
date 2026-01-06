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
public class FilterDeploymentStatus {
    @JsonProperty("flink")
    private TargetDeploymentStatus flink;
    
    @JsonProperty("spring")
    private TargetDeploymentStatus spring;
    
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class TargetDeploymentStatus {
        @JsonProperty("deployed")
        private Boolean deployed;
        
        @JsonProperty("deployedAt")
        private Instant deployedAt;
        
        @JsonProperty("statementIds")
        private List<String> statementIds;
        
        @JsonProperty("error")
        private String error;
    }
}

