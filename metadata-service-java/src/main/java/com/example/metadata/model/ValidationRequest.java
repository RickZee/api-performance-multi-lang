package com.example.metadata.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotNull;
import lombok.Data;

import java.util.Map;

@Data
public class ValidationRequest {
    @JsonProperty("event")
    @NotNull(message = "event field is required")
    private Map<String, Object> event;
    
    @JsonProperty("version")
    private String version;
}
