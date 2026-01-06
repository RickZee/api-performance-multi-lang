package com.example.metadata.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FilterApprovalStatus {
    @JsonProperty("flink")
    private TargetApprovalStatus flink;
    
    @JsonProperty("spring")
    private TargetApprovalStatus spring;
    
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class TargetApprovalStatus {
        @JsonProperty("approved")
        private Boolean approved;
        
        @JsonProperty("approvedAt")
        private Instant approvedAt;
        
        @JsonProperty("approvedBy")
        private String approvedBy;
    }
}

