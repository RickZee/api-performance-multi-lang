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
    
    @NotBlank(message = "Consumer group is required")
    @JsonProperty("consumerGroup")
    private String consumerGroup;
    
    @NotBlank(message = "Output topic is required")
    @JsonProperty("outputTopic")
    private String outputTopic;
    
    @JsonProperty("conditions")
    private FilterConditions conditions;
    
    @JsonProperty("enabled")
    @Builder.Default
    private boolean enabled = true;
    
    @JsonProperty("targets")
    private List<String> targets;
}
