package com.example.streamprocessor.config;

import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Collections;

import static org.assertj.core.api.Assertions.assertThat;

class FilterConfigTest {

    @Test
    void testFilterConfigCreation() {
        // Given
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("equals");
        condition.setValue("CarCreated");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setId("test-filter");
        filterConfig.setName("Test Filter");
        filterConfig.setDescription("Test description");
        filterConfig.setOutputTopic("filtered-test-events");
        filterConfig.setConditionLogic("AND");
        filterConfig.setConditions(Collections.singletonList(condition));

        // Then
        assertThat(filterConfig.getId()).isEqualTo("test-filter");
        assertThat(filterConfig.getName()).isEqualTo("Test Filter");
        assertThat(filterConfig.getDescription()).isEqualTo("Test description");
        assertThat(filterConfig.getOutputTopic()).isEqualTo("filtered-test-events");
        assertThat(filterConfig.getConditionLogic()).isEqualTo("AND");
        assertThat(filterConfig.getConditions()).hasSize(1);
        assertThat(filterConfig.getConditions().get(0).getField()).isEqualTo("event_type");
    }

    @Test
    void testFilterConfigAllArgsConstructor() {
        // Given
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("equals");
        condition.setValue("LoanCreated");

        // When
        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setId("loan-filter");
        filterConfig.setName("Loan Filter");
        filterConfig.setDescription("Filters loan events");
        filterConfig.setOutputTopic("filtered-loan-events");
        filterConfig.setConditionLogic("AND");
        filterConfig.setConditions(Collections.singletonList(condition));

        // Then
        assertThat(filterConfig.getId()).isEqualTo("loan-filter");
        assertThat(filterConfig.getName()).isEqualTo("Loan Filter");
        assertThat(filterConfig.getDescription()).isEqualTo("Filters loan events");
        assertThat(filterConfig.getOutputTopic()).isEqualTo("filtered-loan-events");
        assertThat(filterConfig.getConditionLogic()).isEqualTo("AND");
        assertThat(filterConfig.getConditions()).hasSize(1);
    }

    @Test
    void testFilterConditionCreation() {
        // Given
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("in");
        condition.setValues(Arrays.asList("CarCreated", "LoanCreated"));
        condition.setValueType("string");

        // Then
        assertThat(condition.getField()).isEqualTo("event_type");
        assertThat(condition.getOperator()).isEqualTo("in");
        assertThat(condition.getValues()).containsExactly("CarCreated", "LoanCreated");
        assertThat(condition.getValueType()).isEqualTo("string");
    }

    @Test
    void testFilterConditionAllArgsConstructor() {
        // When
        FilterCondition condition = new FilterCondition(
                "event_type",
                "equals",
                "CarCreated",
                null,
                null,
                null,
                "string"
        );

        // Then
        assertThat(condition.getField()).isEqualTo("event_type");
        assertThat(condition.getOperator()).isEqualTo("equals");
        assertThat(condition.getValue()).isEqualTo("CarCreated");
        assertThat(condition.getValues()).isNull();
        assertThat(condition.getValueType()).isEqualTo("string");
    }
}

