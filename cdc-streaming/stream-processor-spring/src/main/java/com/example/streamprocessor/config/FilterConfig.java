package com.example.streamprocessor.config;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

/**
 * Represents a filter configuration loaded from YAML.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class FilterConfig {
    private String id;
    private String name;
    private String description;
    private String outputTopic;
    private String conditionLogic;
    private List<FilterCondition> conditions;
}

