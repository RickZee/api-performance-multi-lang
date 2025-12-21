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
}

