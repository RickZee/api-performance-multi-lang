package com.example.metadata.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FilterCondition {
    @JsonProperty("field")
    private String field;
    
    @JsonProperty("operator")
    private String operator;
    
    @JsonProperty("value")
    private Object value;
    
    @JsonProperty("values")
    private List<Object> values;
    
    @JsonProperty("min")
    private Object min;
    
    @JsonProperty("max")
    private Object max;
    
    @JsonProperty("valueType")
    private String valueType;
    
    @JsonProperty("logicalOperator")
    private String logicalOperator;
}
