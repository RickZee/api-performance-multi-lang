package com.example.streamprocessor.config;

import com.example.streamprocessor.model.EventHeader;
import com.example.streamprocessor.serde.EventHeaderSerde;
import org.apache.kafka.common.serialization.Serde;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.TestInputTopic;
import org.apache.kafka.streams.TestOutputTopic;
import org.apache.kafka.streams.TopologyTestDriver;
import org.apache.kafka.streams.kstream.KStream;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.Collections;
import java.util.Properties;

import static org.assertj.core.api.Assertions.assertThat;

class KafkaStreamsConfigDynamicTest {

    private TopologyTestDriver testDriver;
    private TestInputTopic<String, EventHeader> inputTopic;
    private KafkaStreamsConfig config;
    private FiltersConfig filtersConfig;

    private final Serde<String> stringSerde = Serdes.String();
    private final Serde<EventHeader> eventHeaderSerde = new EventHeaderSerde();

    @BeforeEach
    void setUp() {
        config = new KafkaStreamsConfig();
        ReflectionTestUtils.setField(config, "sourceTopic", "raw-event-headers");

        // Create test filters configuration
        filtersConfig = new FiltersConfig();
        
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
        carFilter.setConditions(Arrays.asList(carEventTypeCondition, carOpCondition));
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
        loanFilter.setConditions(Arrays.asList(loanEventTypeCondition, loanOpCondition));
        loanFilter.setConditionLogic("AND");

        filtersConfig.setFilters(Arrays.asList(carFilter, loanFilter));
        ReflectionTestUtils.setField(config, "filtersConfig", filtersConfig);

        StreamsBuilder builder = new StreamsBuilder();
        config.eventRoutingStream(builder);

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
    void testCarCreatedEventRouting_WithDynamicFilters() {
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
    }

    @Test
    void testLoanCreatedEventRouting_WithDynamicFilters() {
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
    }

    @Test
    void testEventFilteredOut_WhenOpDoesNotMatch() {
        // Given - CarCreated event but with update operation
        EventHeader event = EventHeader.builder()
                .id("event-3")
                .eventName("CarCreated")
                .eventType("CarCreated")
                .createdDate("2024-01-15T10:30:00Z")
                .savedDate("2024-01-15T10:30:05Z")
                .headerData("{\"uuid\":\"event-3\"}")
                .op("u") // Update operation, not create
                .table("event_headers")
                .build();

        // When
        inputTopic.pipeInput("key-3", event);

        // Then - Should be filtered out
        TestOutputTopic<String, EventHeader> carOutputTopic = testDriver.createOutputTopic(
                "filtered-car-created-events-spring",
                stringSerde.deserializer(),
                eventHeaderSerde.deserializer()
        );

        assertThat(carOutputTopic.isEmpty()).isTrue();
    }

    @Test
    void testEventFilteredOut_WhenEventTypeDoesNotMatch() {
        // Given - Event type that doesn't match any filter
        EventHeader event = EventHeader.builder()
                .id("event-4")
                .eventName("UnknownEvent")
                .eventType("UnknownEvent")
                .createdDate("2024-01-15T10:30:00Z")
                .savedDate("2024-01-15T10:30:05Z")
                .headerData("{\"uuid\":\"event-4\"}")
                .op("c")
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

        TestOutputTopic<String, EventHeader> loanOutputTopic = testDriver.createOutputTopic(
                "filtered-loan-created-events-spring",
                stringSerde.deserializer(),
                eventHeaderSerde.deserializer()
        );

        assertThat(carOutputTopic.isEmpty()).isTrue();
        assertThat(loanOutputTopic.isEmpty()).isTrue();
    }

    @Test
    void testNullEvent_ShouldBeFilteredOut() {
        // When
        inputTopic.pipeInput("key-5", null);

        // Then - Should be filtered out
        TestOutputTopic<String, EventHeader> carOutputTopic = testDriver.createOutputTopic(
                "filtered-car-created-events-spring",
                stringSerde.deserializer(),
                eventHeaderSerde.deserializer()
        );

        assertThat(carOutputTopic.isEmpty()).isTrue();
    }

    @Test
    void testMultipleFilters_ShouldRouteToCorrectTopics() {
        // Given - Car event
        EventHeader carEvent = EventHeader.builder()
                .id("event-car")
                .eventName("CarCreated")
                .eventType("CarCreated")
                .op("c")
                .table("event_headers")
                .build();

        // Given - Loan event
        EventHeader loanEvent = EventHeader.builder()
                .id("event-loan")
                .eventName("LoanCreated")
                .eventType("LoanCreated")
                .op("c")
                .table("event_headers")
                .build();

        // When
        inputTopic.pipeInput("key-car", carEvent);
        inputTopic.pipeInput("key-loan", loanEvent);

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

        var carOutput = carOutputTopic.readKeyValue();
        assertThat(carOutput).isNotNull();
        assertThat(carOutput.value.getEventType()).isEqualTo("CarCreated");

        var loanOutput = loanOutputTopic.readKeyValue();
        assertThat(loanOutput).isNotNull();
        assertThat(loanOutput.value.getEventType()).isEqualTo("LoanCreated");
    }

    @Test
    void testNoFiltersConfig_ShouldNotCrash() {
        // Given - Config without filters
        KafkaStreamsConfig configWithoutFilters = new KafkaStreamsConfig();
        ReflectionTestUtils.setField(configWithoutFilters, "sourceTopic", "raw-event-headers");
        ReflectionTestUtils.setField(configWithoutFilters, "filtersConfig", null);

        StreamsBuilder builder = new StreamsBuilder();
        KStream<String, EventHeader> stream = configWithoutFilters.eventRoutingStream(builder);

        Properties props = new Properties();
        props.put("application.id", "test-app");
        props.put("bootstrap.servers", "dummy:1234");

        TopologyTestDriver testDriverNoFilters = new TopologyTestDriver(builder.build(), props);

        // When - Should not throw exception
        TestInputTopic<String, EventHeader> input = testDriverNoFilters.createInputTopic(
                "raw-event-headers",
                stringSerde.serializer(),
                eventHeaderSerde.serializer()
        );

        EventHeader event = EventHeader.builder()
                .id("event-1")
                .eventType("CarCreated")
                .op("c")
                .build();

        input.pipeInput("key-1", event);

        // Then - Should complete without errors
        testDriverNoFilters.close();
    }

    @Test
    void testInvalidFilterConfig_ShouldBeSkipped() {
        // Given - Filter with null ID
        FilterConfig invalidFilter = new FilterConfig();
        invalidFilter.setId(null); // Invalid
        invalidFilter.setOutputTopic("filtered-invalid-events");

        FiltersConfig invalidFiltersConfig = new FiltersConfig();
        invalidFiltersConfig.setFilters(Collections.singletonList(invalidFilter));

        KafkaStreamsConfig configWithInvalid = new KafkaStreamsConfig();
        ReflectionTestUtils.setField(configWithInvalid, "sourceTopic", "raw-event-headers");
        ReflectionTestUtils.setField(configWithInvalid, "filtersConfig", invalidFiltersConfig);

        StreamsBuilder builder = new StreamsBuilder();
        KStream<String, EventHeader> stream = configWithInvalid.eventRoutingStream(builder);

        Properties props = new Properties();
        props.put("application.id", "test-app");
        props.put("bootstrap.servers", "dummy:1234");

        TopologyTestDriver testDriverInvalid = new TopologyTestDriver(builder.build(), props);

        // When - Should not throw exception
        TestInputTopic<String, EventHeader> input = testDriverInvalid.createInputTopic(
                "raw-event-headers",
                stringSerde.serializer(),
                eventHeaderSerde.serializer()
        );

        EventHeader event = EventHeader.builder()
                .id("event-1")
                .eventType("CarCreated")
                .op("c")
                .build();

        input.pipeInput("key-1", event);

        // Then - Should complete without errors (invalid filter skipped)
        testDriverInvalid.close();
    }
}

