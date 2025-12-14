package com.example.metadata.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CreateFilterRequest {
    @NotBlank(message = "Name is required")
    @JsonProperty("name")
    private String name;
    
    @JsonProperty("description")
    private String description;
    
    @NotBlank(message = "Consumer ID is required")
    @JsonProperty("consumerId")
    private String consumerId;
    
    @NotBlank(message = "Output topic is required")
    @JsonProperty("outputTopic")
    private String outputTopic;
    
    @NotEmpty(message = "At least one condition is required")
    @Size(min = 1, message = "At least one condition is required")
    @JsonProperty("conditions")
    private List<FilterCondition> conditions;
    
    @JsonProperty("enabled")
    private boolean enabled = true;
    
    @JsonProperty("conditionLogic")
    private String conditionLogic = "AND";
}
