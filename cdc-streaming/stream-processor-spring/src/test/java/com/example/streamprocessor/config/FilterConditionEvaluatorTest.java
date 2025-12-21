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
        FilterConfig idFilterConfig = new FilterConfig();
        idFilterConfig.setConditionLogic("AND");
        idFilterConfig.setConditions(Collections.singletonList(idCondition));
        assertThat(FilterConditionEvaluator.createPredicate(idFilterConfig)
                .test(fullEvent)).isTrue();

        // Test event_name field
        FilterCondition nameCondition = new FilterCondition();
        nameCondition.setField("event_name");
        nameCondition.setOperator("equals");
        nameCondition.setValue("TestEvent");
        FilterConfig nameFilterConfig = new FilterConfig();
        nameFilterConfig.setConditionLogic("AND");
        nameFilterConfig.setConditions(Collections.singletonList(nameCondition));
        assertThat(FilterConditionEvaluator.createPredicate(nameFilterConfig)
                .test(fullEvent)).isTrue();

        // Test __ts_ms field
        FilterCondition tsCondition = new FilterCondition();
        tsCondition.setField("__ts_ms");
        tsCondition.setOperator("greaterThan");
        tsCondition.setValue("1000");
        FilterConfig tsFilterConfig = new FilterConfig();
        tsFilterConfig.setConditionLogic("AND");
        tsFilterConfig.setConditions(Collections.singletonList(tsCondition));
        assertThat(FilterConditionEvaluator.createPredicate(tsFilterConfig)
                .test(fullEvent)).isTrue();
    }

    @Test
    void testGreaterThanOperator_Numeric_ShouldMatch() {
        // Given
        EventHeader event = EventHeader.builder()
                .tsMs(2000L)
                .build();

        FilterCondition condition = new FilterCondition();
        condition.setField("__ts_ms");
        condition.setOperator("greaterThan");
        condition.setValue("1000");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(event)).isTrue();
    }

    @Test
    void testGreaterThanOperator_Numeric_ShouldNotMatch() {
        // Given
        EventHeader event = EventHeader.builder()
                .tsMs(500L)
                .build();

        FilterCondition condition = new FilterCondition();
        condition.setField("__ts_ms");
        condition.setOperator("greaterThan");
        condition.setValue("1000");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(event)).isFalse();
    }

    @Test
    void testGreaterThanOperator_String_ShouldMatch() {
        // Given
        EventHeader event = EventHeader.builder()
                .eventType("CarCreated")
                .build();

        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("greaterThan");
        condition.setValue("Car");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(event)).isTrue();
    }

    @Test
    void testLessThanOperator_Numeric_ShouldMatch() {
        // Given
        EventHeader event = EventHeader.builder()
                .tsMs(500L)
                .build();

        FilterCondition condition = new FilterCondition();
        condition.setField("__ts_ms");
        condition.setOperator("lessThan");
        condition.setValue("1000");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(event)).isTrue();
    }

    @Test
    void testLessThanOperator_Numeric_ShouldNotMatch() {
        // Given
        EventHeader event = EventHeader.builder()
                .tsMs(2000L)
                .build();

        FilterCondition condition = new FilterCondition();
        condition.setField("__ts_ms");
        condition.setOperator("lessThan");
        condition.setValue("1000");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(event)).isFalse();
    }

    @Test
    void testLessThanOperator_String_ShouldMatch() {
        // Given
        EventHeader event = EventHeader.builder()
                .eventType("Car")
                .build();

        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("lessThan");
        condition.setValue("CarCreated");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(event)).isTrue();
    }

    @Test
    void testGreaterThanOrEqualOperator_ShouldMatch() {
        // Given
        EventHeader event = EventHeader.builder()
                .tsMs(1000L)
                .build();

        FilterCondition condition = new FilterCondition();
        condition.setField("__ts_ms");
        condition.setOperator("greaterThanOrEqual");
        condition.setValue("1000");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(event)).isTrue();
    }

    @Test
    void testGreaterThanOrEqualOperator_ShouldNotMatch() {
        // Given
        EventHeader event = EventHeader.builder()
                .tsMs(500L)
                .build();

        FilterCondition condition = new FilterCondition();
        condition.setField("__ts_ms");
        condition.setOperator("greaterThanOrEqual");
        condition.setValue("1000");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(event)).isFalse();
    }

    @Test
    void testLessThanOrEqualOperator_ShouldMatch() {
        // Given
        EventHeader event = EventHeader.builder()
                .tsMs(1000L)
                .build();

        FilterCondition condition = new FilterCondition();
        condition.setField("__ts_ms");
        condition.setOperator("lessThanOrEqual");
        condition.setValue("1000");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(event)).isTrue();
    }

    @Test
    void testLessThanOrEqualOperator_ShouldNotMatch() {
        // Given
        EventHeader event = EventHeader.builder()
                .tsMs(2000L)
                .build();

        FilterCondition condition = new FilterCondition();
        condition.setField("__ts_ms");
        condition.setOperator("lessThanOrEqual");
        condition.setValue("1000");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(event)).isFalse();
    }

    @Test
    void testBetweenOperator_Numeric_ShouldMatch() {
        // Given
        EventHeader event = EventHeader.builder()
                .tsMs(1500L)
                .build();

        FilterCondition condition = new FilterCondition();
        condition.setField("__ts_ms");
        condition.setOperator("between");
        condition.setMin("1000");
        condition.setMax("2000");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(event)).isTrue();
    }

    @Test
    void testBetweenOperator_Numeric_ShouldMatchBoundaries() {
        // Given
        EventHeader eventMin = EventHeader.builder().tsMs(1000L).build();
        EventHeader eventMax = EventHeader.builder().tsMs(2000L).build();

        FilterCondition condition = new FilterCondition();
        condition.setField("__ts_ms");
        condition.setOperator("between");
        condition.setMin("1000");
        condition.setMax("2000");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(eventMin)).isTrue();
        assertThat(predicate.test(eventMax)).isTrue();
    }

    @Test
    void testBetweenOperator_Numeric_ShouldNotMatch() {
        // Given
        EventHeader eventBelow = EventHeader.builder().tsMs(500L).build();
        EventHeader eventAbove = EventHeader.builder().tsMs(2500L).build();

        FilterCondition condition = new FilterCondition();
        condition.setField("__ts_ms");
        condition.setOperator("between");
        condition.setMin("1000");
        condition.setMax("2000");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(eventBelow)).isFalse();
        assertThat(predicate.test(eventAbove)).isFalse();
    }

    @Test
    void testBetweenOperator_String_ShouldMatch() {
        // Given
        EventHeader event = EventHeader.builder()
                .eventType("CarCreated")
                .build();

        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("between");
        condition.setMin("Car");
        condition.setMax("Loan");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(event)).isTrue();
    }

    @Test
    void testMatchesOperator_WithWildcard_ShouldMatch() {
        // Given
        EventHeader event = EventHeader.builder()
                .eventType("CarCreated")
                .build();

        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("matches");
        condition.setValue("Car%");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(event)).isTrue();
    }

    @Test
    void testMatchesOperator_WithWildcard_ShouldNotMatch() {
        // Given
        EventHeader event = EventHeader.builder()
                .eventType("LoanCreated")
                .build();

        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("matches");
        condition.setValue("Car%");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(event)).isFalse();
    }

    @Test
    void testMatchesOperator_WithUnderscore_ShouldMatch() {
        // Given
        EventHeader event = EventHeader.builder()
                .eventType("Car_Created")
                .build();

        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("matches");
        condition.setValue("Car_Created");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(event)).isTrue();
    }

    @Test
    void testMatchesOperator_WithMultipleWildcards_ShouldMatch() {
        // Given
        EventHeader event = EventHeader.builder()
                .eventType("CarCreatedEvent")
                .build();

        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("matches");
        condition.setValue("%Created%");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(event)).isTrue();
    }

    @Test
    void testComparisonOperators_WithNullField_ShouldReturnFalse() {
        // Given
        EventHeader event = EventHeader.builder()
                .tsMs(null)
                .build();

        FilterCondition condition = new FilterCondition();
        condition.setField("__ts_ms");
        condition.setOperator("greaterThan");
        condition.setValue("1000");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(event)).isFalse();
    }

    @Test
    void testBetweenOperator_WithNullField_ShouldReturnFalse() {
        // Given
        EventHeader event = EventHeader.builder()
                .tsMs(null)
                .build();

        FilterCondition condition = new FilterCondition();
        condition.setField("__ts_ms");
        condition.setOperator("between");
        condition.setMin("1000");
        condition.setMax("2000");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(event)).isFalse();
    }

    @Test
    void testMatchesOperator_WithNullField_ShouldReturnFalse() {
        // Given
        EventHeader event = EventHeader.builder()
                .eventType(null)
                .build();

        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("matches");
        condition.setValue("Car%");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(event)).isFalse();
    }

    @Test
    void testUnknownOperator_ShouldReturnFalse() {
        // Given
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("unknownOperator");
        condition.setValue("CarCreated");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(testEvent)).isFalse();
    }

    @Test
    void testUnknownField_ShouldReturnFalse() {
        // Given
        FilterCondition condition = new FilterCondition();
        condition.setField("unknown_field");
        condition.setOperator("equals");
        condition.setValue("value");

        FilterConfig filterConfig = new FilterConfig();
        filterConfig.setConditions(Collections.singletonList(condition));

        // When
        Predicate<EventHeader> predicate = FilterConditionEvaluator.createPredicate(filterConfig);

        // Then
        assertThat(predicate.test(testEvent)).isFalse();
    }
}

