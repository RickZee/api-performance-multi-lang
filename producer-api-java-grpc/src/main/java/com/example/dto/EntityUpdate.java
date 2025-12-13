package com.example.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.Map;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class EntityUpdate {
    private String entityType;
    private String entityId;
    private Map<String, Object> updatedAttributes;
}

