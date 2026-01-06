package com.example.metadata.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotBlank;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CompatibilityRequest {
    @NotBlank(message = "oldVersion is required")
    @JsonProperty("oldVersion")
    private String oldVersion;
    
    @NotBlank(message = "newVersion is required")
    @JsonProperty("newVersion")
    private String newVersion;
    
    @JsonProperty("type")
    private String type; // Optional, defaults to "event"
}

