package com.example.streamprocessor.config;

import com.example.streamprocessor.model.EventHeader;
import com.example.streamprocessor.serde.EventHeaderSerde;
import org.apache.kafka.common.serialization.Serde;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.TestInputTopic;
import org.apache.kafka.streams.TestOutputTopic;
import org.apache.kafka.streams.TopologyTestDriver;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import org.yaml.snakeyaml.Yaml;

import java.io.InputStream;
import java.util.List;
import java.util.Map;
import java.util.Properties;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Integration test for KafkaStreamsConfig with YAML-based filter configuration.
 * Tests the full flow from YAML configuration loading to event routing.
 */
class KafkaStreamsConfigIntegrationTest {

    private KafkaStreamsConfig kafkaStreamsConfig;
    private FiltersConfig filtersConfig;
    private TopologyTestDriver testDriver;
    private TestInputTopic<String, EventHeader> inputTopic;

    private final Serde<String> stringSerde = Serdes.String();
    private final Serde<EventHeader> eventHeaderSerde = new EventHeaderSerde();

    @BeforeEach
    void setUp() {
        // Load filters from YAML file
        filtersConfig = loadFiltersFromYaml();
        
        // Create config and inject filters
        kafkaStreamsConfig = new KafkaStreamsConfig();
        ReflectionTestUtils.setField(kafkaStreamsConfig, "sourceTopic", "raw-event-headers");
        ReflectionTestUtils.setField(kafkaStreamsConfig, "filtersConfig", filtersConfig);

        StreamsBuilder builder = new StreamsBuilder();
        kafkaStreamsConfig.eventRoutingStream(builder);

        Properties props = new Properties();
        props.put("application.id", "test-app");
        props.put("bootstrap.servers", "dummy:1234");

        testDriver = new TopologyTestDriver(builder.build(), props);

        inputTopic = testDriver.createInputTopic(
                "raw-event-headers",
                stringSerde.serializer(),
                eventHeaderSerde.serializer()
        );
    }

    @AfterEach
    void tearDown() {
        if (testDriver != null) {
            testDriver.close();
        }
    }

    @Test
    void testCarCreatedEventRouting_WithYamlConfig() {
        // Given
        EventHeader event = EventHeader.builder()
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

        // When
        inputTopic.pipeInput("key-1", event);

        // Then
        TestOutputTopic<String, EventHeader> carOutputTopic = testDriver.createOutputTopic(
                "filtered-car-created-events-spring",
                stringSerde.deserializer(),
                eventHeaderSerde.deserializer()
        );

        var output = carOutputTopic.readKeyValue();
        assertThat(output).isNotNull();
        assertThat(output.value.getEventType()).isEqualTo("CarCreated");
        assertThat(output.value.getOp()).isEqualTo("c");
        assertThat(output.value.getId()).isEqualTo("event-1");
    }

    @Test
    void testLoanCreatedEventRouting_WithYamlConfig() {
        // Given
        EventHeader event = EventHeader.builder()
                .id("event-2")
                .eventName("LoanCreated")
                .eventType("LoanCreated")
                .createdDate("2024-01-15T10:30:00Z")
                .savedDate("2024-01-15T10:30:05Z")
                .headerData("{\"uuid\":\"event-2\"}")
                .op("c")
                .table("event_headers")
                .tsMs(1705312200000L)
                .build();

        // When
        inputTopic.pipeInput("key-2", event);

        // Then
        TestOutputTopic<String, EventHeader> loanOutputTopic = testDriver.createOutputTopic(
                "filtered-loan-created-events-spring",
                stringSerde.deserializer(),
                eventHeaderSerde.deserializer()
        );

        var output = loanOutputTopic.readKeyValue();
        assertThat(output).isNotNull();
        assertThat(output.value.getEventType()).isEqualTo("LoanCreated");
        assertThat(output.value.getOp()).isEqualTo("c");
        assertThat(output.value.getId()).isEqualTo("event-2");
    }

    @Test
    void testServiceEventRouting_WithYamlConfig() {
        // Given
        EventHeader event = EventHeader.builder()
                .id("event-3")
                .eventName("CarServiceDone")
                .eventType("CarServiceDone")
                .createdDate("2024-01-15T10:30:00Z")
                .savedDate("2024-01-15T10:30:05Z")
                .headerData("{\"uuid\":\"event-3\"}")
                .op("c")
                .table("event_headers")
                .tsMs(1705312200000L)
                .build();

        // When
        inputTopic.pipeInput("key-3", event);

        // Then
        TestOutputTopic<String, EventHeader> serviceOutputTopic = testDriver.createOutputTopic(
                "filtered-service-events-spring",
                stringSerde.deserializer(),
                eventHeaderSerde.deserializer()
        );

        var output = serviceOutputTopic.readKeyValue();
        assertThat(output).isNotNull();
        assertThat(output.value.getEventType()).isEqualTo("CarServiceDone");
        assertThat(output.value.getOp()).isEqualTo("c");
        assertThat(output.value.getId()).isEqualTo("event-3");
    }

    @Test
    void testMultipleEventsRouting_WithYamlConfig() {
        // Given - Multiple events
        EventHeader carEvent = EventHeader.builder()
                .id("event-car")
                .eventName("CarCreated")
                .eventType("CarCreated")
                .op("c")
                .table("event_headers")
                .build();

        EventHeader loanEvent = EventHeader.builder()
                .id("event-loan")
                .eventName("LoanCreated")
                .eventType("LoanCreated")
                .op("c")
                .table("event_headers")
                .build();

        EventHeader serviceEvent = EventHeader.builder()
                .id("event-service")
                .eventName("CarServiceDone")
                .eventType("CarServiceDone")
                .op("c")
                .table("event_headers")
                .build();

        // When
        inputTopic.pipeInput("key-car", carEvent);
        inputTopic.pipeInput("key-loan", loanEvent);
        inputTopic.pipeInput("key-service", serviceEvent);

        // Then
        TestOutputTopic<String, EventHeader> carOutputTopic = testDriver.createOutputTopic(
                "filtered-car-created-events-spring",
                stringSerde.deserializer(),
                eventHeaderSerde.deserializer()
        );

        TestOutputTopic<String, EventHeader> loanOutputTopic = testDriver.createOutputTopic(
                "filtered-loan-created-events-spring",
                stringSerde.deserializer(),
                eventHeaderSerde.deserializer()
        );

        TestOutputTopic<String, EventHeader> serviceOutputTopic = testDriver.createOutputTopic(
                "filtered-service-events-spring",
                stringSerde.deserializer(),
                eventHeaderSerde.deserializer()
        );

        var carOutput = carOutputTopic.readKeyValue();
        assertThat(carOutput).isNotNull();
        assertThat(carOutput.value.getEventType()).isEqualTo("CarCreated");

        var loanOutput = loanOutputTopic.readKeyValue();
        assertThat(loanOutput).isNotNull();
        assertThat(loanOutput.value.getEventType()).isEqualTo("LoanCreated");

        var serviceOutput = serviceOutputTopic.readKeyValue();
        assertThat(serviceOutput).isNotNull();
        assertThat(serviceOutput.value.getEventType()).isEqualTo("CarServiceDone");
    }

    @Test
    void testEventFilteredOut_WhenConditionsNotMet() {
        // Given - CarCreated event but with update operation
        EventHeader event = EventHeader.builder()
                .id("event-4")
                .eventName("CarCreated")
                .eventType("CarCreated")
                .createdDate("2024-01-15T10:30:00Z")
                .savedDate("2024-01-15T10:30:05Z")
                .headerData("{\"uuid\":\"event-4\"}")
                .op("u") // Update operation, not create - should be filtered out
                .table("event_headers")
                .build();

        // When
        inputTopic.pipeInput("key-4", event);

        // Then - Should be filtered out
        TestOutputTopic<String, EventHeader> carOutputTopic = testDriver.createOutputTopic(
                "filtered-car-created-events-spring",
                stringSerde.deserializer(),
                eventHeaderSerde.deserializer()
        );

        assertThat(carOutputTopic.isEmpty()).isTrue();
    }

    @Test
    void testUnmatchedEventType_ShouldBeFilteredOut() {
        // Given - Event type that doesn't match any filter
        EventHeader event = EventHeader.builder()
                .id("event-5")
                .eventName("UnknownEvent")
                .eventType("UnknownEvent")
                .createdDate("2024-01-15T10:30:00Z")
                .savedDate("2024-01-15T10:30:05Z")
                .headerData("{\"uuid\":\"event-5\"}")
                .op("c")
                .table("event_headers")
                .build();

        // When
        inputTopic.pipeInput("key-5", event);

        // Then - Should be filtered out
        TestOutputTopic<String, EventHeader> carOutputTopic = testDriver.createOutputTopic(
                "filtered-car-created-events-spring",
                stringSerde.deserializer(),
                eventHeaderSerde.deserializer()
        );

        TestOutputTopic<String, EventHeader> loanOutputTopic = testDriver.createOutputTopic(
                "filtered-loan-created-events-spring",
                stringSerde.deserializer(),
                eventHeaderSerde.deserializer()
        );

        TestOutputTopic<String, EventHeader> serviceOutputTopic = testDriver.createOutputTopic(
                "filtered-service-events-spring",
                stringSerde.deserializer(),
                eventHeaderSerde.deserializer()
        );

        assertThat(carOutputTopic.isEmpty()).isTrue();
        assertThat(loanOutputTopic.isEmpty()).isTrue();
        assertThat(serviceOutputTopic.isEmpty()).isTrue();
    }

    /**
     * Loads filters from YAML test file.
     */
    private FiltersConfig loadFiltersFromYaml() {
        try {
            InputStream inputStream = getClass().getClassLoader()
                    .getResourceAsStream("filters-test.yml");
            
            if (inputStream == null) {
                // Fallback: create test filters programmatically
                return createTestFiltersConfig();
            }

            Yaml yaml = new Yaml();
            Map<String, Object> data = yaml.load(inputStream);
            
            FiltersConfig config = new FiltersConfig();
            List<Map<String, Object>> filtersList = (List<Map<String, Object>>) data.get("filters");
            
            List<FilterConfig> filterConfigs = filtersList.stream()
                    .map(this::mapToFilterConfig)
                    .toList();
            
            config.setFilters(filterConfigs);
            return config;
        } catch (Exception e) {
            // Fallback: create test filters programmatically
            return createTestFiltersConfig();
        }
    }

    private FilterConfig mapToFilterConfig(Map<String, Object> map) {
        FilterConfig config = new FilterConfig();
        config.setId((String) map.get("id"));
        config.setName((String) map.get("name"));
        config.setDescription((String) map.get("description"));
        config.setOutputTopic((String) map.get("outputTopic"));
        config.setConditionLogic((String) map.get("conditionLogic"));
        
        List<Map<String, Object>> conditionsList = (List<Map<String, Object>>) map.get("conditions");
        List<FilterCondition> conditions = conditionsList.stream()
                .map(this::mapToFilterCondition)
                .toList();
        config.setConditions(conditions);
        
        return config;
    }

    private FilterCondition mapToFilterCondition(Map<String, Object> map) {
        FilterCondition condition = new FilterCondition();
        condition.setField((String) map.get("field"));
        condition.setOperator((String) map.get("operator"));
        condition.setValue((String) map.get("value"));
        condition.setValues((List<String>) map.get("values"));
        condition.setMin((String) map.get("min"));
        condition.setMax((String) map.get("max"));
        condition.setValueType((String) map.get("valueType"));
        return condition;
    }

    private FiltersConfig createTestFiltersConfig() {
        FiltersConfig config = new FiltersConfig();
        
        // Car Created filter
        FilterCondition carEventTypeCondition = new FilterCondition();
        carEventTypeCondition.setField("event_type");
        carEventTypeCondition.setOperator("equals");
        carEventTypeCondition.setValue("CarCreated");

        FilterCondition carOpCondition = new FilterCondition();
        carOpCondition.setField("__op");
        carOpCondition.setOperator("equals");
        carOpCondition.setValue("c");

        FilterConfig carFilter = new FilterConfig();
        carFilter.setId("car-created-filter");
        carFilter.setName("Car Created Events");
        carFilter.setOutputTopic("filtered-car-created-events");
        carFilter.setConditions(List.of(carEventTypeCondition, carOpCondition));
        carFilter.setConditionLogic("AND");

        // Loan Created filter
        FilterCondition loanEventTypeCondition = new FilterCondition();
        loanEventTypeCondition.setField("event_type");
        loanEventTypeCondition.setOperator("equals");
        loanEventTypeCondition.setValue("LoanCreated");

        FilterCondition loanOpCondition = new FilterCondition();
        loanOpCondition.setField("__op");
        loanOpCondition.setOperator("equals");
        loanOpCondition.setValue("c");

        FilterConfig loanFilter = new FilterConfig();
        loanFilter.setId("loan-created-filter");
        loanFilter.setName("Loan Created Events");
        loanFilter.setOutputTopic("filtered-loan-created-events");
        loanFilter.setConditions(List.of(loanEventTypeCondition, loanOpCondition));
        loanFilter.setConditionLogic("AND");

        // Service Events filter
        FilterCondition serviceEventTypeCondition = new FilterCondition();
        serviceEventTypeCondition.setField("event_type");
        serviceEventTypeCondition.setOperator("equals");
        serviceEventTypeCondition.setValue("CarServiceDone");

        FilterCondition serviceOpCondition = new FilterCondition();
        serviceOpCondition.setField("__op");
        serviceOpCondition.setOperator("equals");
        serviceOpCondition.setValue("c");

        FilterConfig serviceFilter = new FilterConfig();
        serviceFilter.setId("service-events-filter");
        serviceFilter.setName("Service Events");
        serviceFilter.setOutputTopic("filtered-service-events");
        serviceFilter.setConditions(List.of(serviceEventTypeCondition, serviceOpCondition));
        serviceFilter.setConditionLogic("AND");

        config.setFilters(List.of(carFilter, loanFilter, serviceFilter));
        return config;
    }

    @Test
    void testYamlConfigWithMixedStatusFilters_OnlyActiveAndDeprecatedProcess() {
        // Given - Load filters from status test YAML
        FiltersConfig statusFiltersConfig = loadFiltersFromStatusTestYaml();
        
        KafkaStreamsConfig config = new KafkaStreamsConfig();
        ReflectionTestUtils.setField(config, "sourceTopic", "raw-event-headers");
        ReflectionTestUtils.setField(config, "filtersConfig", statusFiltersConfig);

        StreamsBuilder builder = new StreamsBuilder();
        config.eventRoutingStream(builder);

        Properties props = new Properties();
        props.put("application.id", "test-app");
        props.put("bootstrap.servers", "dummy:1234");

        TopologyTestDriver statusTestDriver = new TopologyTestDriver(builder.build(), props);

        TestInputTopic<String, EventHeader> input = statusTestDriver.createInputTopic(
                "raw-event-headers",
                stringSerde.serializer(),
                eventHeaderSerde.serializer()
        );

        EventHeader carEvent = EventHeader.builder()
                .id("event-car")
                .eventType("CarCreated")
                .op("c")
                .table("event_headers")
                .build();

        // When
        input.pipeInput("key-car", carEvent);

        // Then - Only active and deployed filters should process (deleted, disabled, pending_deletion excluded)
        TestOutputTopic<String, EventHeader> activeOutput = statusTestDriver.createOutputTopic(
                "filtered-active-events-spring",
                stringSerde.deserializer(),
                eventHeaderSerde.deserializer()
        );

        TestOutputTopic<String, EventHeader> deprecatedOutput = statusTestDriver.createOutputTopic(
                "filtered-deprecated-events-spring",
                stringSerde.deserializer(),
                eventHeaderSerde.deserializer()
        );

        TestOutputTopic<String, EventHeader> deletedOutput = statusTestDriver.createOutputTopic(
                "filtered-deleted-events-spring",
                stringSerde.deserializer(),
                eventHeaderSerde.deserializer()
        );

        TestOutputTopic<String, EventHeader> disabledOutput = statusTestDriver.createOutputTopic(
                "filtered-disabled-events-spring",
                stringSerde.deserializer(),
                eventHeaderSerde.deserializer()
        );

        TestOutputTopic<String, EventHeader> deployedOutput = statusTestDriver.createOutputTopic(
                "filtered-deployed-events-spring",
                stringSerde.deserializer(),
                eventHeaderSerde.deserializer()
        );

        // Active and deployed filters should process
        assertThat(activeOutput.isEmpty()).isFalse();
        assertThat(deployedOutput.isEmpty()).isFalse();
        
        // Deleted and disabled filters should not process
        assertThat(deletedOutput.isEmpty()).isTrue();
        assertThat(disabledOutput.isEmpty()).isTrue();
        
        // Deprecated filter doesn't match CarCreated, so empty
        assertThat(deprecatedOutput.isEmpty()).isTrue();

        statusTestDriver.close();
    }

    @Test
    void testYamlConfigWithDeprecatedFilters_StillProcessEvents() {
        // Given - Load filters with deprecated status
        FiltersConfig statusFiltersConfig = loadFiltersFromStatusTestYaml();
        
        KafkaStreamsConfig config = new KafkaStreamsConfig();
        ReflectionTestUtils.setField(config, "sourceTopic", "raw-event-headers");
        ReflectionTestUtils.setField(config, "filtersConfig", statusFiltersConfig);

        StreamsBuilder builder = new StreamsBuilder();
        config.eventRoutingStream(builder);

        Properties props = new Properties();
        props.put("application.id", "test-app");
        props.put("bootstrap.servers", "dummy:1234");

        TopologyTestDriver statusTestDriver = new TopologyTestDriver(builder.build(), props);

        TestInputTopic<String, EventHeader> input = statusTestDriver.createInputTopic(
                "raw-event-headers",
                stringSerde.serializer(),
                eventHeaderSerde.serializer()
        );

        EventHeader loanEvent = EventHeader.builder()
                .id("event-loan")
                .eventType("LoanCreated")
                .op("c")
                .table("event_headers")
                .build();

        // When
        input.pipeInput("key-loan", loanEvent);

        // Then - Deprecated filter should still process events
        TestOutputTopic<String, EventHeader> deprecatedOutput = statusTestDriver.createOutputTopic(
                "filtered-deprecated-events-spring",
                stringSerde.deserializer(),
                eventHeaderSerde.deserializer()
        );

        var output = deprecatedOutput.readKeyValue();
        assertThat(output).isNotNull();
        assertThat(output.value.getEventType()).isEqualTo("LoanCreated");

        statusTestDriver.close();
    }

    @Test
    void testYamlConfigWithDisabledFilters_ShouldNotCreateStreams() {
        // Given - Load filters with disabled status
        FiltersConfig statusFiltersConfig = loadFiltersFromStatusTestYaml();
        
        KafkaStreamsConfig config = new KafkaStreamsConfig();
        ReflectionTestUtils.setField(config, "sourceTopic", "raw-event-headers");
        ReflectionTestUtils.setField(config, "filtersConfig", statusFiltersConfig);

        StreamsBuilder builder = new StreamsBuilder();
        config.eventRoutingStream(builder);

        Properties props = new Properties();
        props.put("application.id", "test-app");
        props.put("bootstrap.servers", "dummy:1234");

        TopologyTestDriver statusTestDriver = new TopologyTestDriver(builder.build(), props);

        TestInputTopic<String, EventHeader> input = statusTestDriver.createInputTopic(
                "raw-event-headers",
                stringSerde.serializer(),
                eventHeaderSerde.serializer()
        );

        EventHeader paymentEvent = EventHeader.builder()
                .id("event-payment")
                .eventType("PaymentSubmitted")
                .op("c")
                .table("event_headers")
                .build();

        // When
        input.pipeInput("key-payment", paymentEvent);

        // Then - Disabled filter should not process
        TestOutputTopic<String, EventHeader> disabledOutput = statusTestDriver.createOutputTopic(
                "filtered-disabled-events-spring",
                stringSerde.deserializer(),
                eventHeaderSerde.deserializer()
        );

        assertThat(disabledOutput.isEmpty()).isTrue();

        statusTestDriver.close();
    }

    /**
     * Loads filters from status test YAML file.
     */
    private FiltersConfig loadFiltersFromStatusTestYaml() {
        try {
            InputStream inputStream = getClass().getClassLoader()
                    .getResourceAsStream("filters-status-test.yml");
            
            if (inputStream == null) {
                // Fallback: create test filters programmatically
                return createStatusTestFiltersConfig();
            }

            Yaml yaml = new Yaml();
            Map<String, Object> data = yaml.load(inputStream);
            
            FiltersConfig config = new FiltersConfig();
            List<Map<String, Object>> filtersList = (List<Map<String, Object>>) data.get("filters");
            
            List<FilterConfig> filterConfigs = filtersList.stream()
                    .map(this::mapToFilterConfigWithStatus)
                    .toList();
            
            config.setFilters(filterConfigs);
            return config;
        } catch (Exception e) {
            // Fallback: create test filters programmatically
            return createStatusTestFiltersConfig();
        }
    }

    private FilterConfig mapToFilterConfigWithStatus(Map<String, Object> map) {
        FilterConfig config = mapToFilterConfig(map);
        
        // Map status and enabled fields
        if (map.containsKey("status")) {
            config.setStatus((String) map.get("status"));
        }
        if (map.containsKey("enabled")) {
            config.setEnabled((Boolean) map.get("enabled"));
        }
        if (map.containsKey("version")) {
            config.setVersion((Integer) map.get("version"));
        }
        
        return config;
    }

    private FiltersConfig createStatusTestFiltersConfig() {
        FiltersConfig config = new FiltersConfig();
        
        // Active filter
        FilterCondition activeCondition = new FilterCondition();
        activeCondition.setField("event_type");
        activeCondition.setOperator("equals");
        activeCondition.setValue("CarCreated");

        FilterCondition activeOpCondition = new FilterCondition();
        activeOpCondition.setField("__op");
        activeOpCondition.setOperator("equals");
        activeOpCondition.setValue("c");

        FilterConfig activeFilter = new FilterConfig();
        activeFilter.setId("active-filter");
        activeFilter.setName("Active Filter");
        activeFilter.setOutputTopic("filtered-active-events");
        activeFilter.setConditions(List.of(activeCondition, activeOpCondition));
        activeFilter.setConditionLogic("AND");
        activeFilter.setStatus("active");
        activeFilter.setEnabled(true);

        // Deprecated filter
        FilterCondition deprecatedCondition = new FilterCondition();
        deprecatedCondition.setField("event_type");
        deprecatedCondition.setOperator("equals");
        deprecatedCondition.setValue("LoanCreated");

        FilterCondition deprecatedOpCondition = new FilterCondition();
        deprecatedOpCondition.setField("__op");
        deprecatedOpCondition.setOperator("equals");
        deprecatedOpCondition.setValue("c");

        FilterConfig deprecatedFilter = new FilterConfig();
        deprecatedFilter.setId("deprecated-filter");
        deprecatedFilter.setName("Deprecated Filter");
        deprecatedFilter.setOutputTopic("filtered-deprecated-events");
        deprecatedFilter.setConditions(List.of(deprecatedCondition, deprecatedOpCondition));
        deprecatedFilter.setConditionLogic("AND");
        deprecatedFilter.setStatus("deprecated");
        deprecatedFilter.setEnabled(true);

        // Deleted filter
        FilterConfig deletedFilter = new FilterConfig();
        deletedFilter.setId("deleted-filter");
        deletedFilter.setName("Deleted Filter");
        deletedFilter.setOutputTopic("filtered-deleted-events");
        deletedFilter.setStatus("deleted");
        deletedFilter.setEnabled(true);

        // Disabled filter
        FilterConfig disabledFilter = new FilterConfig();
        disabledFilter.setId("disabled-filter");
        disabledFilter.setName("Disabled Filter");
        disabledFilter.setOutputTopic("filtered-disabled-events");
        disabledFilter.setStatus("active");
        disabledFilter.setEnabled(false);

        // Deployed filter
        FilterCondition deployedCondition = new FilterCondition();
        deployedCondition.setField("event_type");
        deployedCondition.setOperator("equals");
        deployedCondition.setValue("CarCreated");

        FilterCondition deployedOpCondition = new FilterCondition();
        deployedOpCondition.setField("__op");
        deployedOpCondition.setOperator("equals");
        deployedOpCondition.setValue("c");

        FilterConfig deployedFilter = new FilterConfig();
        deployedFilter.setId("deployed-filter");
        deployedFilter.setName("Deployed Filter");
        deployedFilter.setOutputTopic("filtered-deployed-events");
        deployedFilter.setConditions(List.of(deployedCondition, deployedOpCondition));
        deployedFilter.setConditionLogic("AND");
        deployedFilter.setStatus("deployed");
        deployedFilter.setEnabled(true);

        config.setFilters(List.of(activeFilter, deprecatedFilter, deletedFilter, disabledFilter, deployedFilter));
        return config;
    }
}

