package com.example.metadata.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class UpdateFilterStatusRequest {
    @JsonProperty("status")
    private String status;
    
    @JsonProperty("approvedBy")
    private String approvedBy;
    
    @JsonProperty("notes")
    private String notes;
}

