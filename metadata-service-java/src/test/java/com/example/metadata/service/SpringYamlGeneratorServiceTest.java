package com.example.metadata.service;

import com.example.metadata.model.Filter;
import com.example.metadata.model.FilterCondition;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class SpringYamlGeneratorServiceTest {

    private SpringYamlGeneratorService service;

    @BeforeEach
    void setUp() {
        service = new SpringYamlGeneratorService();
    }

    @Test
    void testGenerateYamlFromSingleFilter() {
        Filter filter = createTestFilter("test-filter", "Test Filter", "filtered-test-events");
        
        String yaml = service.generateYaml(List.of(filter));
        
        assertThat(yaml).isNotNull();
        assertThat(yaml).contains("id: test-filter");
        assertThat(yaml).contains("name: Test Filter");
        assertThat(yaml).contains("outputTopic: filtered-test-events-spring");
        assertThat(yaml).contains("conditionLogic: AND");
        assertThat(yaml).contains("enabled: true");
        assertThat(yaml).contains("conditions:");
    }

    @Test
    void testGenerateYamlFromMultipleFilters() {
        Filter filter1 = createTestFilter("filter-1", "Filter 1", "filtered-events-1");
        Filter filter2 = createTestFilter("filter-2", "Filter 2", "filtered-events-2");
        
        String yaml = service.generateYaml(List.of(filter1, filter2));
        
        assertThat(yaml).contains("id: filter-1");
        assertThat(yaml).contains("id: filter-2");
        assertThat(yaml).contains("name: Filter 1");
        assertThat(yaml).contains("name: Filter 2");
    }

    @Test
    void testExcludeDisabledFilters() {
        Filter enabledFilter = createTestFilter("enabled-filter", "Enabled", "filtered-enabled");
        Filter disabledFilter = createTestFilter("disabled-filter", "Disabled", "filtered-disabled");
        disabledFilter.setEnabled(false);
        
        String yaml = service.generateYaml(List.of(enabledFilter, disabledFilter));
        
        assertThat(yaml).contains("id: enabled-filter");
        assertThat(yaml).doesNotContain("id: disabled-filter");
    }

    @Test
    void testExcludeDeletedFilters() {
        Filter activeFilter = createTestFilter("active-filter", "Active", "filtered-active");
        Filter deletedFilter = createTestFilter("deleted-filter", "Deleted", "filtered-deleted");
        deletedFilter.setStatus("deleted");
        
        String yaml = service.generateYaml(List.of(activeFilter, deletedFilter));
        
        assertThat(yaml).contains("id: active-filter");
        assertThat(yaml).doesNotContain("id: deleted-filter");
    }

    @Test
    void testExcludePendingDeletionFilters() {
        Filter activeFilter = createTestFilter("active-filter", "Active", "filtered-active");
        Filter pendingFilter = createTestFilter("pending-filter", "Pending", "filtered-pending");
        pendingFilter.setStatus("pending_deletion");
        
        String yaml = service.generateYaml(List.of(activeFilter, pendingFilter));
        
        assertThat(yaml).contains("id: active-filter");
        assertThat(yaml).doesNotContain("id: pending-filter");
    }

    @Test
    void testHandleAllConditionOperators() {
        List<FilterCondition> conditions = new ArrayList<>();
        
        // Equals condition
        conditions.add(FilterCondition.builder()
            .field("event_type")
            .operator("equals")
            .value("TestEvent")
            .valueType("string")
            .build());
        
        // Greater than condition
        conditions.add(FilterCondition.builder()
            .field("amount")
            .operator("greaterThan")
            .value(100)
            .valueType("number")
            .build());
        
        // In condition
        conditions.add(FilterCondition.builder()
            .field("status")
            .operator("in")
            .values(Arrays.asList("active", "pending"))
            .valueType("string")
            .build());
        
        Filter filter = createTestFilter("test-filter", "Test", "filtered-test");
        filter.setConditions(conditions);
        
        String yaml = service.generateYaml(List.of(filter));
        
        assertThat(yaml).contains("operator: equals");
        assertThat(yaml).contains("operator: greaterThan");
        assertThat(yaml).contains("operator: in");
        assertThat(yaml).contains("value: \"TestEvent\"");
        assertThat(yaml).contains("value: 100");
        assertThat(yaml).contains("values:");
    }

    @Test
    void testGenerateEmptyYamlWhenNoFilters() {
        String yaml = service.generateYaml(List.of());
        
        assertThat(yaml).isNotNull();
        assertThat(yaml).contains("filters: []");
    }

    @Test
    void testGenerateEmptyYamlWhenAllFiltersDisabled() {
        Filter filter1 = createTestFilter("filter-1", "Filter 1", "filtered-1");
        filter1.setEnabled(false);
        Filter filter2 = createTestFilter("filter-2", "Filter 2", "filtered-2");
        filter2.setEnabled(false);
        
        String yaml = service.generateYaml(List.of(filter1, filter2));
        
        assertThat(yaml).contains("filters: []");
    }

    @Test
    void testAddSpringSuffixToOutputTopic() {
        Filter filter = createTestFilter("test-filter", "Test", "filtered-test");
        
        String yaml = service.generateYaml(List.of(filter));
        
        assertThat(yaml).contains("outputTopic: filtered-test-spring");
    }

    @Test
    void testPreserveSpringSuffixIfAlreadyPresent() {
        Filter filter = createTestFilter("test-filter", "Test", "filtered-test-spring");
        
        String yaml = service.generateYaml(List.of(filter));
        
        assertThat(yaml).contains("outputTopic: filtered-test-spring");
    }

    @Test
    void testIncludeDescription() {
        Filter filter = createTestFilter("test-filter", "Test", "filtered-test");
        filter.setDescription("Test description");
        
        String yaml = service.generateYaml(List.of(filter));
        
        assertThat(yaml).contains("description: Test description");
    }

    @Test
    void testHandleNullDescription() {
        Filter filter = createTestFilter("test-filter", "Test", "filtered-test");
        filter.setDescription(null);
        
        String yaml = service.generateYaml(List.of(filter));
        
        assertThat(yaml).doesNotContain("description:");
    }

    @Test
    void testHandleORConditionLogic() {
        Filter filter = createTestFilter("test-filter", "Test", "filtered-test");
        filter.setConditionLogic("OR");
        
        String yaml = service.generateYaml(List.of(filter));
        
        assertThat(yaml).contains("conditionLogic: OR");
    }

    @Test
    void testDefaultToANDConditionLogic() {
        Filter filter = createTestFilter("test-filter", "Test", "filtered-test");
        filter.setConditionLogic(null);
        
        String yaml = service.generateYaml(List.of(filter));
        
        assertThat(yaml).contains("conditionLogic: AND");
    }

    @Test
    void testWarnAboutDeprecatedFilters() {
        Filter activeFilter = createTestFilter("active-filter", "Active", "filtered-active");
        Filter deprecatedFilter = createTestFilter("deprecated-filter", "Deprecated", "filtered-deprecated");
        deprecatedFilter.setStatus("deprecated");
        
        String yaml = service.generateYaml(List.of(activeFilter, deprecatedFilter));
        
        assertThat(yaml).contains("# WARNING: The following filters are deprecated");
        assertThat(yaml).contains("#   - deprecated-filter");
        assertThat(yaml).contains("id: deprecated-filter"); // Should still be included
    }

    @Test
    void testYamlHeader() {
        Filter filter = createTestFilter("test-filter", "Test", "filtered-test");
        
        String yaml = service.generateYaml(List.of(filter));
        
        assertThat(yaml).contains("# Generated Spring Boot Filter Configuration");
        assertThat(yaml).contains("# Generated at:");
        assertThat(yaml).contains("# Source: Metadata Service API");
        assertThat(yaml).contains("# DO NOT EDIT MANUALLY");
    }

    private Filter createTestFilter(String id, String name, String outputTopic) {
        FilterCondition condition = FilterCondition.builder()
            .field("event_type")
            .operator("equals")
            .value("TestEvent")
            .valueType("string")
            .build();
        
        return Filter.builder()
            .id(id)
            .name(name)
            .outputTopic(outputTopic)
            .enabled(true)
            .conditionLogic("AND")
            .conditions(List.of(condition))
            .status("deployed")
            .build();
    }
}

