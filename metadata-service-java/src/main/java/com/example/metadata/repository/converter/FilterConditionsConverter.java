package com.example.metadata.repository.converter;

import com.example.metadata.model.FilterCondition;
import com.example.metadata.model.FilterConditions;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

import java.util.ArrayList;
import java.util.List;

@Converter
public class FilterConditionsConverter implements AttributeConverter<FilterConditions, String> {
    
    private final ObjectMapper objectMapper;
    
    public FilterConditionsConverter() {
        this.objectMapper = new ObjectMapper();
        this.objectMapper.registerModule(new JavaTimeModule());
    }
    
    @Override
    public String convertToDatabaseColumn(FilterConditions filterConditions) {
        if (filterConditions == null) {
            return "{\"logic\":\"AND\",\"conditions\":[]}";
        }
        try {
            return objectMapper.writeValueAsString(filterConditions);
        } catch (Exception e) {
            throw new RuntimeException("Error converting conditions to JSON", e);
        }
    }
    
    @Override
    public FilterConditions convertToEntityAttribute(String json) {
        if (json == null || json.trim().isEmpty() || json.trim().equals("[]")) {
            return FilterConditions.builder()
                .logic("AND")
                .conditions(new ArrayList<>())
                .build();
        }
        try {
            // Handle legacy format (array of conditions) - migrate on read
            if (json.trim().startsWith("[")) {
                List<FilterCondition> conditions = objectMapper.readValue(json, new TypeReference<List<FilterCondition>>() {});
                return FilterConditions.builder()
                    .logic("AND")
                    .conditions(conditions != null ? conditions : new ArrayList<>())
                    .build();
            }
            // New format (object with logic and conditions)
            return objectMapper.readValue(json, FilterConditions.class);
        } catch (Exception e) {
            throw new RuntimeException("Error converting JSON to conditions", e);
        }
    }
}

