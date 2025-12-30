package com.example.metadata.repository.entity;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.persistence.Embeddable;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

@Embeddable
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class FilterConditionEmbeddable {
    
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

