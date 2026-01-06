package com.example.metadata.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.ArrayList;
import java.util.List;

/**
 * Wrapper for filter conditions that includes the logic operator (AND/OR)
 * and the list of conditions.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FilterConditions {
    @JsonProperty("logic")
    @Builder.Default
    private String logic = "AND";
    
    @JsonProperty("conditions")
    @Builder.Default
    private List<FilterCondition> conditions = new ArrayList<>();
}

