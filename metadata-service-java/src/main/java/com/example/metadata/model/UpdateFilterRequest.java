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
    
    @JsonProperty("consumerId")
    private String consumerId;
    
    @JsonProperty("outputTopic")
    private String outputTopic;
    
    @JsonProperty("conditions")
    private List<FilterCondition> conditions;
    
    @JsonProperty("enabled")
    private Boolean enabled;
    
    @JsonProperty("conditionLogic")
    private String conditionLogic;
}
