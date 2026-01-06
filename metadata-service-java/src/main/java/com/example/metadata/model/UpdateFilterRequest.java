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
public class UpdateFilterRequest {
    @JsonProperty("name")
    private String name;
    
    @JsonProperty("description")
    private String description;
    
    @JsonProperty("consumerGroup")
    private String consumerGroup;
    
    @JsonProperty("outputTopic")
    private String outputTopic;
    
    @JsonProperty("conditions")
    private FilterConditions conditions;
    
    @JsonProperty("enabled")
    private Boolean enabled;
    
    @JsonProperty("targets")
    private List<String> targets;
}
