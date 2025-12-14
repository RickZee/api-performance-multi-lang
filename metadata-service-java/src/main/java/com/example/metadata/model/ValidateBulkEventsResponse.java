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
public class ValidateBulkEventsResponse {
    @JsonProperty("results")
    private List<ValidationResponse> results;
    
    @JsonProperty("summary")
    private BulkSummary summary;
    
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class BulkSummary {
        @JsonProperty("total")
        private int total;
        
        @JsonProperty("valid")
        private int valid;
        
        @JsonProperty("invalid")
        private int invalid;
    }
}
