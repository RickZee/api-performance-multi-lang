package com.example.metadata.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.Map;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class SchemaResponse {
    @JsonProperty("version")
    private String version;
    
    @JsonProperty("schema")
    private Map<String, Object> schema;
}
