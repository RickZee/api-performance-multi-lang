package com.example.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotNull;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.time.Instant;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class EntityHeader {

    @NotNull(message = "entityId is required")
    @JsonProperty("entityId")
    private String entityId;

    @NotNull(message = "entityType is required")
    @JsonProperty("entityType")
    private String entityType;

    @NotNull(message = "createdAt is required")
    @JsonProperty("createdAt")
    private Instant createdAt;

    @NotNull(message = "updatedAt is required")
    @JsonProperty("updatedAt")
    private Instant updatedAt;
}
