package com.example.metadata.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import lombok.Data;

import java.util.List;
import java.util.Map;

@Data
public class ValidateBulkEventsRequest {
    @JsonProperty("events")
    @NotNull(message = "events field is required")
    private List<Map<String, Object>> events;
    
    @JsonProperty("version")
    private String version;
}
