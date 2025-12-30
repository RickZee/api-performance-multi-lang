package com.example.metadata.repository.converter;

import com.example.metadata.model.FilterCondition;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

import java.util.ArrayList;
import java.util.List;

@Converter
public class FilterConditionsConverter implements AttributeConverter<List<FilterCondition>, String> {
    
    private final ObjectMapper objectMapper;
    
    public FilterConditionsConverter() {
        this.objectMapper = new ObjectMapper();
        this.objectMapper.registerModule(new JavaTimeModule());
    }
    
    @Override
    public String convertToDatabaseColumn(List<FilterCondition> conditions) {
        if (conditions == null || conditions.isEmpty()) {
            return "[]";
        }
        try {
            return objectMapper.writeValueAsString(conditions);
        } catch (Exception e) {
            throw new RuntimeException("Error converting conditions to JSON", e);
        }
    }
    
    @Override
    public List<FilterCondition> convertToEntityAttribute(String json) {
        if (json == null || json.trim().isEmpty()) {
            return new ArrayList<>();
        }
        try {
            return objectMapper.readValue(json, new TypeReference<List<FilterCondition>>() {});
        } catch (Exception e) {
            throw new RuntimeException("Error converting JSON to conditions", e);
        }
    }
}

