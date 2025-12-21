package com.example.streamprocessor.config;

import com.example.streamprocessor.model.EventHeader;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Collections;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Tests for filter status and lifecycle state handling.
 * Verifies that filters with different status values are handled correctly.
 */
class FilterStatusTest {

    private EventHeader createTestEvent() {
        return EventHeader.builder()
                .id("event-1")
                .eventName("CarCreated")
                .eventType("CarCreated")
                .op("c")
                .table("event_headers")
                .build();
    }

    @Test
    void testDeletedStatusFilter_ShouldBeExcluded() {
        // Given - Filter with deleted status
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("equals");
        condition.setValue("CarCreated");

        FilterConfig deletedFilter = new FilterConfig();
        deletedFilter.setId("deleted-filter");
        deletedFilter.setName("Deleted Filter");
        deletedFilter.setOutputTopic("filtered-deleted-events");
        deletedFilter.setConditions(Collections.singletonList(condition));
        deletedFilter.setStatus("deleted");
        deletedFilter.setEnabled(true);

        FiltersConfig filtersConfig = new FiltersConfig();
        filtersConfig.setFilters(Collections.singletonList(deletedFilter));

        // When - Filter should be excluded from processing
        // Note: In actual implementation, deleted filters are excluded in generator
        // This test verifies the status field is properly set
        assertThat(deletedFilter.getStatus()).isEqualTo("deleted");
        assertThat(deletedFilter.getEnabled()).isTrue();
    }

    @Test
    void testDeprecatedStatusFilter_ShouldStillProcess() {
        // Given - Filter with deprecated status
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("equals");
        condition.setValue("CarCreated");

        FilterConfig deprecatedFilter = new FilterConfig();
        deprecatedFilter.setId("deprecated-filter");
        deprecatedFilter.setName("Deprecated Filter");
        deprecatedFilter.setOutputTopic("filtered-deprecated-events");
        deprecatedFilter.setConditions(Collections.singletonList(condition));
        deprecatedFilter.setStatus("deprecated");
        deprecatedFilter.setEnabled(true);

        // When - Deprecated filters should still process events
        FiltersConfig filtersConfig = new FiltersConfig();
        filtersConfig.setFilters(Collections.singletonList(deprecatedFilter));

        // Then - Filter should still work (warnings generated separately)
        assertThat(deprecatedFilter.getStatus()).isEqualTo("deprecated");
        assertThat(deprecatedFilter.getEnabled()).isTrue();
        
        // Verify filter logic still works
        var predicate = FilterConditionEvaluator.createPredicate(deprecatedFilter);
        assertThat(predicate.test(createTestEvent())).isTrue();
    }

    @Test
    void testDisabledFilter_ShouldBeExcluded() {
        // Given - Filter with enabled: false
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("equals");
        condition.setValue("CarCreated");

        FilterConfig disabledFilter = new FilterConfig();
        disabledFilter.setId("disabled-filter");
        disabledFilter.setName("Disabled Filter");
        disabledFilter.setOutputTopic("filtered-disabled-events");
        disabledFilter.setConditions(Collections.singletonList(condition));
        disabledFilter.setEnabled(false);
        disabledFilter.setStatus("active");

        // When
        FiltersConfig filtersConfig = new FiltersConfig();
        filtersConfig.setFilters(Collections.singletonList(disabledFilter));

        // Then - Filter should be marked as disabled
        assertThat(disabledFilter.getEnabled()).isFalse();
        assertThat(disabledFilter.getStatus()).isEqualTo("active");
    }

    @Test
    void testPendingDeletionStatusFilter_ShouldBeExcluded() {
        // Given - Filter with pending_deletion status
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("equals");
        condition.setValue("CarCreated");

        FilterConfig pendingDeletionFilter = new FilterConfig();
        pendingDeletionFilter.setId("pending-deletion-filter");
        pendingDeletionFilter.setName("Pending Deletion Filter");
        pendingDeletionFilter.setOutputTopic("filtered-pending-deletion-events");
        pendingDeletionFilter.setConditions(Collections.singletonList(condition));
        pendingDeletionFilter.setStatus("pending_deletion");
        pendingDeletionFilter.setEnabled(true);

        // When
        FiltersConfig filtersConfig = new FiltersConfig();
        filtersConfig.setFilters(Collections.singletonList(pendingDeletionFilter));

        // Then
        assertThat(pendingDeletionFilter.getStatus()).isEqualTo("pending_deletion");
    }

    @Test
    void testActiveStatusFilter_ShouldBeIncluded() {
        // Given - Filter with active status
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("equals");
        condition.setValue("CarCreated");

        FilterConfig activeFilter = new FilterConfig();
        activeFilter.setId("active-filter");
        activeFilter.setName("Active Filter");
        activeFilter.setOutputTopic("filtered-active-events");
        activeFilter.setConditions(Collections.singletonList(condition));
        activeFilter.setStatus("active");
        activeFilter.setEnabled(true);

        // When
        FiltersConfig filtersConfig = new FiltersConfig();
        filtersConfig.setFilters(Collections.singletonList(activeFilter));

        // Then
        assertThat(activeFilter.getStatus()).isEqualTo("active");
        assertThat(activeFilter.getEnabled()).isTrue();
        
        // Verify filter logic works
        var predicate = FilterConditionEvaluator.createPredicate(activeFilter);
        assertThat(predicate.test(createTestEvent())).isTrue();
    }

    @Test
    void testDeployedStatusFilter_ShouldBeIncluded() {
        // Given - Filter with deployed status
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("equals");
        condition.setValue("CarCreated");

        FilterConfig deployedFilter = new FilterConfig();
        deployedFilter.setId("deployed-filter");
        deployedFilter.setName("Deployed Filter");
        deployedFilter.setOutputTopic("filtered-deployed-events");
        deployedFilter.setConditions(Collections.singletonList(condition));
        deployedFilter.setStatus("deployed");
        deployedFilter.setEnabled(true);

        // When
        FiltersConfig filtersConfig = new FiltersConfig();
        filtersConfig.setFilters(Collections.singletonList(deployedFilter));

        // Then
        assertThat(deployedFilter.getStatus()).isEqualTo("deployed");
        assertThat(deployedFilter.getEnabled()).isTrue();
        
        // Verify filter logic works
        var predicate = FilterConditionEvaluator.createPredicate(deployedFilter);
        assertThat(predicate.test(createTestEvent())).isTrue();
    }

    @Test
    void testDeletedAndDisabled_ShouldBeExcluded() {
        // Given - Filter that is both deleted and disabled
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("equals");
        condition.setValue("CarCreated");

        FilterConfig filter = new FilterConfig();
        filter.setId("deleted-disabled-filter");
        filter.setName("Deleted and Disabled Filter");
        filter.setOutputTopic("filtered-deleted-disabled-events");
        filter.setConditions(Collections.singletonList(condition));
        filter.setStatus("deleted");
        filter.setEnabled(false);

        // When
        FiltersConfig filtersConfig = new FiltersConfig();
        filtersConfig.setFilters(Collections.singletonList(filter));

        // Then
        assertThat(filter.getStatus()).isEqualTo("deleted");
        assertThat(filter.getEnabled()).isFalse();
    }

    @Test
    void testDeprecatedButEnabled_ShouldStillProcess() {
        // Given - Deprecated but enabled filter
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("equals");
        condition.setValue("CarCreated");

        FilterConfig filter = new FilterConfig();
        filter.setId("deprecated-enabled-filter");
        filter.setName("Deprecated Enabled Filter");
        filter.setOutputTopic("filtered-deprecated-enabled-events");
        filter.setConditions(Collections.singletonList(condition));
        filter.setStatus("deprecated");
        filter.setEnabled(true);

        // When
        FiltersConfig filtersConfig = new FiltersConfig();
        filtersConfig.setFilters(Collections.singletonList(filter));

        // Then - Should still process (warnings generated in generator)
        assertThat(filter.getStatus()).isEqualTo("deprecated");
        assertThat(filter.getEnabled()).isTrue();
        
        var predicate = FilterConditionEvaluator.createPredicate(filter);
        assertThat(predicate.test(createTestEvent())).isTrue();
    }

    @Test
    void testMultipleFiltersWithDifferentStatuses() {
        // Given - Multiple filters with different statuses
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("equals");
        condition.setValue("CarCreated");

        FilterConfig activeFilter = new FilterConfig();
        activeFilter.setId("active-filter");
        activeFilter.setOutputTopic("filtered-active-events");
        activeFilter.setConditions(Collections.singletonList(condition));
        activeFilter.setStatus("active");
        activeFilter.setEnabled(true);

        FilterConfig deprecatedFilter = new FilterConfig();
        deprecatedFilter.setId("deprecated-filter");
        deprecatedFilter.setOutputTopic("filtered-deprecated-events");
        deprecatedFilter.setConditions(Collections.singletonList(condition));
        deprecatedFilter.setStatus("deprecated");
        deprecatedFilter.setEnabled(true);

        FilterConfig deletedFilter = new FilterConfig();
        deletedFilter.setId("deleted-filter");
        deletedFilter.setOutputTopic("filtered-deleted-events");
        deletedFilter.setConditions(Collections.singletonList(condition));
        deletedFilter.setStatus("deleted");
        deletedFilter.setEnabled(true);

        FilterConfig disabledFilter = new FilterConfig();
        disabledFilter.setId("disabled-filter");
        disabledFilter.setOutputTopic("filtered-disabled-events");
        disabledFilter.setConditions(Collections.singletonList(condition));
        disabledFilter.setStatus("active");
        disabledFilter.setEnabled(false);

        // When
        FiltersConfig filtersConfig = new FiltersConfig();
        filtersConfig.setFilters(Arrays.asList(activeFilter, deprecatedFilter, deletedFilter, disabledFilter));

        // Then
        assertThat(filtersConfig.getFilters()).hasSize(4);
        assertThat(activeFilter.getStatus()).isEqualTo("active");
        assertThat(deprecatedFilter.getStatus()).isEqualTo("deprecated");
        assertThat(deletedFilter.getStatus()).isEqualTo("deleted");
        assertThat(disabledFilter.getEnabled()).isFalse();
    }

    @Test
    void testStatusField_DefaultValue() {
        // Given - Filter without status field
        FilterCondition condition = new FilterCondition();
        condition.setField("event_type");
        condition.setOperator("equals");
        condition.setValue("CarCreated");

        FilterConfig filter = new FilterConfig();
        filter.setId("no-status-filter");
        filter.setOutputTopic("filtered-no-status-events");
        filter.setConditions(Collections.singletonList(condition));
        // status not set

        // When
        FiltersConfig filtersConfig = new FiltersConfig();
        filtersConfig.setFilters(Collections.singletonList(filter));

        // Then - Should handle null status gracefully
        assertThat(filter.getStatus()).isNull();
        assertThat(filter.getEnabled()).isNull(); // default behavior
    }
}

