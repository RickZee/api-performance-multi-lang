package com.example.streamprocessor.config;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * Represents a single filter condition.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class FilterCondition {
    private String field;
    private String operator;
    private String value;
    private List<String> values;
    private String min;
    private String max;
    private String valueType;
}

