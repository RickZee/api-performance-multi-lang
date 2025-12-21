package com.example.streamprocessor.config;

import com.example.streamprocessor.model.EventHeader;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.function.Predicate;

import static org.assertj.core.api.Assertions.assertThat;

class FilterConditionEvaluatorTest {

    private EventHeader testEvent;

    @BeforeEach
    void setUp() {
        testEvent = EventHeader.builder()
                .id("event-1")
                .eventName("CarCreated")
                .eventType("CarCreated")
                .createdDate("2024-01-15T10:30:00Z")
                .savedDate("2024-01-15T10:30:05Z")
                .headerData("{\"uuid\":\"event-1\"}")
                .op("c")
                .table("event_headers")
                .tsMs(1705312200000L)
                .build();
    }

    @Test
    void testEqualsOperator_ShouldMatch() {
        // Given
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("equals");
        condition.setValue("CarCreated");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(testEvent)).isTrue();
    }

    @Test
    void testEqualsOperator_ShouldNotMatch() {
        // Given
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("equals");
        condition.setValue("LoanCreated");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(testEvent)).isFalse();
    }

    @Test
    void testInOperator_ShouldMatch() {
        // Given
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("in");
        condition.setValues(Arrays.asList("CarCreated", "LoanCreated", "ServiceDone"));

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(testEvent)).isTrue();
    }

    @Test
    void testInOperator_ShouldNotMatch() {
        // Given
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("in");
        condition.setValues(Arrays.asList("LoanCreated", "ServiceDone"));

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(testEvent)).isFalse();
    }

    @Test
    void testNotInOperator_ShouldMatch() {
        // Given
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("notIn");
        condition.setValues(Arrays.asList("LoanCreated", "ServiceDone"));

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(testEvent)).isTrue();
    }

    @Test
    void testNotInOperator_ShouldNotMatch() {
        // Given
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("notIn");
        condition.setValues(Arrays.asList("CarCreated", "LoanCreated"));

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(testEvent)).isFalse();
    }

    @Test
    void testIsNullOperator_ShouldMatch() {
        // Given
        EventHeader nullFieldEvent = EventHeader.builder()
                .id("event-2")
                .eventType("Test")
                .op(null) // null field
                .build();

        FilterCondition condition = new FilterCondition();
        condition.setField("__op");
        condition.setOperator("isNull");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(nullFieldEvent)).isTrue();
        assertThat(predicate.test(testEvent)).isFalse();
    }

    @Test
    void testIsNotNullOperator_ShouldMatch() {
        // Given
        FilterCondition condition = new FilterCondition();
        condition.setField("__op");
        condition.setOperator("isNotNull");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(testEvent)).isTrue();
    }

    @Test
    void testMultipleConditionsWithAndLogic_AllMatch() {
        // Given
        FilterCondition condition1 = new FilterCondition();
        condition1.setField("event_type");
        condition1.setOperator("equals");
        condition1.setValue("CarCreated");

        FilterCondition condition2 = new FilterCondition();
        condition2.setField("__op");
        condition2.setOperator("equals");
        condition2.setValue("c");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Arrays.asList(condition1, condition2));
        filterConfig.setConditionLogic("AND");

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(testEvent)).isTrue();
    }

    @Test
    void testMultipleConditionsWithAndLogic_OneDoesNotMatch() {
        // Given
        FilterCondition condition1 = new FilterCondition();
        condition1.setField("event_type");
        condition1.setOperator("equals");
        condition1.setValue("CarCreated");

        FilterCondition condition2 = new FilterCondition();
        condition2.setField("__op");
        condition2.setOperator("equals");
        condition2.setValue("u"); // Doesn't match

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Arrays.asList(condition1, condition2));
        filterConfig.setConditionLogic("AND");

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(testEvent)).isFalse();
    }

    @Test
    void testMultipleConditionsWithOrLogic_OneMatches() {
        // Given
        FilterCondition condition1 = new FilterCondition();
        condition1.setField("event_type");
        condition1.setOperator("equals");
        condition1.setValue("LoanCreated"); // Doesn't match

        FilterCondition condition2 = new FilterCondition();
        condition2.setField("event_type");
        condition2.setOperator("equals");
        condition2.setValue("CarCreated"); // Matches

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Arrays.asList(condition1, condition2));
        filterConfig.setConditionLogic("OR");

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(testEvent)).isTrue();
    }

    @Test
    void testMultipleConditionsWithOrLogic_NoneMatch() {
        // Given
        FilterCondition condition1 = new FilterCondition();
        condition1.setField("event_type");
        condition1.setOperator("equals");
        condition1.setValue("LoanCreated"); // Doesn't match

        FilterCondition condition2 = new FilterCondition();
        condition2.setField("event_type");
        condition2.setOperator("equals");
        condition2.setValue("ServiceDone"); // Doesn't match

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Arrays.asList(condition1, condition2));
        filterConfig.setConditionLogic("OR");

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(testEvent)).isFalse();
    }

    @Test
    void testNullEvent_ShouldReturnFalse() {
        // Given
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("equals");
        condition.setValue("CarCreated");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(null)).isFalse();
    }

    @Test
    void testEmptyConditions_ShouldReturnFalse() {
        // Given
        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.emptyList());

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(testEvent)).isFalse();
    }

    @Test
    void testNullFilterConfig_ShouldReturnFalse() {
        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(null);

        // Then
        assertThat(predicate.test(testEvent)).isFalse();
    }

    @Test
    void testAllEventFields() {
        // Test each field can be accessed
        EventHeader fullEvent = EventHeader.builder()
                .id("test-id")
                .eventName("TestEvent")
                .eventType("TestType")
                .createdDate("2024-01-01T00:00:00Z")
                .savedDate("2024-01-01T00:00:01Z")
                .headerData("{\"test\":\"data\"}")
                .op("c")
                .table("test_table")
                .tsMs(1704067200000L)
                .build();

        // Test id field
        FilterCondition idCondition = new FilterCondition();
        idCondition.setField("id");
        idCondition.setOperator("equals");
        idCondition.setValue("test-id");
        assertThat(FilterConditionEvaluator.createPredicate(
                new FilterConfig(null, null, null, null, "AND", Collections.singletonList(idCondition)))
                .test(fullEvent)).isTrue();

        // Test event_name field
        FilterCondition nameCondition = new FilterCondition();
        nameCondition.setField("event_name");
        nameCondition.setOperator("equals");
        nameCondition.setValue("TestEvent");
        assertThat(FilterConditionEvaluator.createPredicate(
                new FilterConfig(null, null, null, null, "AND", Collections.singletonList(nameCondition)))
                .test(fullEvent)).isTrue();

        // Test __ts_ms field
        FilterCondition tsCondition = new FilterCondition();
        tsCondition.setField("__ts_ms");
        tsCondition.setOperator("greaterThan");
        tsCondition.setValue("1000");
        assertThat(FilterConditionEvaluator.createPredicate(
                new FilterConfig(null, null, null, null, "AND", Collections.singletonList(tsCondition)))
                .test(fullEvent)).isTrue();
    }
}

