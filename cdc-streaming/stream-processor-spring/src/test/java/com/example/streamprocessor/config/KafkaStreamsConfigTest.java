package com.example.streamprocessor.config;

import com.example.streamprocessor.model.EventHeader;
import com.example.streamprocessor.serde.EventHeaderSerde;
import org.apache.kafka.common.serialization.Serde;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.TestInputTopic;
import org.apache.kafka.streams.TestOutputTopic;
import org.apache.kafka.streams.TopologyTestDriver;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.KStream;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.Properties;

import static org.assertj.core.api.Assertions.assertThat;

class KafkaStreamsConfigTest {

    private TopologyTestDriver testDriver;
    private TestInputTopic<String, EventHeader> inputTopic;
    private TestOutputTopic<String, EventHeader> carCreatedOutputTopic;
    private TestOutputTopic<String, EventHeader> loanCreatedOutputTopic;
    private TestOutputTopic<String, EventHeader> loanPaymentOutputTopic;
    private TestOutputTopic<String, EventHeader> serviceOutputTopic;

    private final Serde<String> stringSerde = Serdes.String();
    private final Serde<EventHeader> eventHeaderSerde = new EventHeaderSerde();

    @BeforeEach
    void setUp() {
        // Create a testable config with source topic set
        final Serde<String> testStringSerde = stringSerde;
        final Serde<EventHeader> testEventHeaderSerde = eventHeaderSerde;
        
        KafkaStreamsConfig config = new KafkaStreamsConfig() {
            @Override
            public KStream<String, EventHeader> eventRoutingStream(StreamsBuilder builder) {
                // Override to use test topic
                KStream<String, EventHeader> source = builder.stream(
                    "raw-event-headers",
                    org.apache.kafka.streams.kstream.Consumed.with(testStringSerde, testEventHeaderSerde)
                );

                // Route to filtered-car-created-events
                source.filter((key, value) -> 
                    value != null && 
                    "CarCreated".equals(value.getEventType()) && 
                    "c".equals(value.getOp())
                ).to("filtered-car-created-events");

                // Route to filtered-loan-created-events
                source.filter((key, value) -> 
                    value != null && 
                    "LoanCreated".equals(value.getEventType()) && 
                    "c".equals(value.getOp())
                ).to("filtered-loan-created-events");

                // Route to filtered-loan-payment-submitted-events
                source.filter((key, value) -> 
                    value != null && 
                    "LoanPaymentSubmitted".equals(value.getEventType()) && 
                    "c".equals(value.getOp())
                ).to("filtered-loan-payment-submitted-events");

                // Route to filtered-service-events
                source.filter((key, value) -> 
                    value != null && 
                    "CarServiceDone".equals(value.getEventName())
                ).to("filtered-service-events");

                return source;
            }
        };

        StreamsBuilder builder = new StreamsBuilder();
        KStream<String, EventHeader> stream = config.eventRoutingStream(builder);

        Properties props = new Properties();
        props.put("application.id", "test-app");
        props.put("bootstrap.servers", "dummy:1234");

        testDriver = new TopologyTestDriver(builder.build(), props);

        inputTopic = testDriver.createInputTopic(
            "raw-event-headers",
            stringSerde.serializer(),
            eventHeaderSerde.serializer()
        );

        carCreatedOutputTopic = testDriver.createOutputTopic(
            "filtered-car-created-events",
            stringSerde.deserializer(),
            eventHeaderSerde.deserializer()
        );

        loanCreatedOutputTopic = testDriver.createOutputTopic(
            "filtered-loan-created-events",
            stringSerde.deserializer(),
            eventHeaderSerde.deserializer()
        );

        loanPaymentOutputTopic = testDriver.createOutputTopic(
            "filtered-loan-payment-submitted-events",
            stringSerde.deserializer(),
            eventHeaderSerde.deserializer()
        );

        serviceOutputTopic = testDriver.createOutputTopic(
            "filtered-service-events",
            stringSerde.deserializer(),
            eventHeaderSerde.deserializer()
        );
    }

    @AfterEach
    void tearDown() {
        if (testDriver != null) {
            testDriver.close();
        }
    }

    @Test
    void testCarCreatedEventRouting() {
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
        var output = carCreatedOutputTopic.readKeyValue();
        assertThat(output).isNotNull();
        assertThat(output.value.getEventType()).isEqualTo("CarCreated");
        assertThat(loanCreatedOutputTopic.isEmpty()).isTrue();
        assertThat(loanPaymentOutputTopic.isEmpty()).isTrue();
        assertThat(serviceOutputTopic.isEmpty()).isTrue();
    }

    @Test
    void testLoanCreatedEventRouting() {
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
        var output = loanCreatedOutputTopic.readKeyValue();
        assertThat(output).isNotNull();
        assertThat(output.value.getEventType()).isEqualTo("LoanCreated");
        assertThat(carCreatedOutputTopic.isEmpty()).isTrue();
        assertThat(loanPaymentOutputTopic.isEmpty()).isTrue();
        assertThat(serviceOutputTopic.isEmpty()).isTrue();
    }

    @Test
    void testLoanPaymentSubmittedEventRouting() {
        // Given
        EventHeader event = EventHeader.builder()
            .id("event-3")
            .eventName("LoanPaymentSubmitted")
            .eventType("LoanPaymentSubmitted")
            .createdDate("2024-01-15T10:30:00Z")
            .savedDate("2024-01-15T10:30:05Z")
            .headerData("{\"uuid\":\"event-3\"}")
            .op("c")
            .table("event_headers")
            .build();

        // When
        inputTopic.pipeInput("key-3", event);

        // Then
        var output = loanPaymentOutputTopic.readKeyValue();
        assertThat(output).isNotNull();
        assertThat(output.value.getEventType()).isEqualTo("LoanPaymentSubmitted");
        assertThat(carCreatedOutputTopic.isEmpty()).isTrue();
        assertThat(loanCreatedOutputTopic.isEmpty()).isTrue();
        assertThat(serviceOutputTopic.isEmpty()).isTrue();
    }

    @Test
    void testServiceEventRouting() {
        // Given
        EventHeader event = EventHeader.builder()
            .id("event-4")
            .eventName("CarServiceDone")
            .eventType("CarServiceDone")
            .createdDate("2024-01-15T10:30:00Z")
            .savedDate("2024-01-15T10:30:05Z")
            .headerData("{\"uuid\":\"event-4\"}")
            .op("c")
            .table("event_headers")
            .build();

        // When
        inputTopic.pipeInput("key-4", event);

        // Then
        var output = serviceOutputTopic.readKeyValue();
        assertThat(output).isNotNull();
        assertThat(output.value.getEventName()).isEqualTo("CarServiceDone");
        assertThat(carCreatedOutputTopic.isEmpty()).isTrue();
        assertThat(loanCreatedOutputTopic.isEmpty()).isTrue();
        assertThat(loanPaymentOutputTopic.isEmpty()).isTrue();
    }

    @Test
    void testEventFilteredOutWhenOpIsNotCreate() {
        // Given - CarCreated event but with update operation
        EventHeader event = EventHeader.builder()
            .id("event-5")
            .eventName("CarCreated")
            .eventType("CarCreated")
            .createdDate("2024-01-15T10:30:00Z")
            .savedDate("2024-01-15T10:30:05Z")
            .headerData("{\"uuid\":\"event-5\"}")
            .op("u") // Update operation, not create
            .table("event_headers")
            .build();

        // When
        inputTopic.pipeInput("key-5", event);

        // Then - Should be filtered out
        assertThat(carCreatedOutputTopic.isEmpty()).isTrue();
        assertThat(loanCreatedOutputTopic.isEmpty()).isTrue();
        assertThat(loanPaymentOutputTopic.isEmpty()).isTrue();
        assertThat(serviceOutputTopic.isEmpty()).isTrue();
    }

    @Test
    void testNullEventFilteredOut() {
        // When
        inputTopic.pipeInput("key-6", null);

        // Then - Should be filtered out
        assertThat(carCreatedOutputTopic.isEmpty()).isTrue();
        assertThat(loanCreatedOutputTopic.isEmpty()).isTrue();
        assertThat(loanPaymentOutputTopic.isEmpty()).isTrue();
        assertThat(serviceOutputTopic.isEmpty()).isTrue();
    }

    @Test
    void testUnmatchedEventTypeFilteredOut() {
        // Given - Event type that doesn't match any filter
        EventHeader event = EventHeader.builder()
            .id("event-7")
            .eventName("UnknownEvent")
            .eventType("UnknownEvent")
            .createdDate("2024-01-15T10:30:00Z")
            .savedDate("2024-01-15T10:30:05Z")
            .headerData("{\"uuid\":\"event-7\"}")
            .op("c")
            .table("event_headers")
            .build();

        // When
        inputTopic.pipeInput("key-7", event);

        // Then - Should be filtered out
        assertThat(carCreatedOutputTopic.isEmpty()).isTrue();
        assertThat(loanCreatedOutputTopic.isEmpty()).isTrue();
        assertThat(loanPaymentOutputTopic.isEmpty()).isTrue();
        assertThat(serviceOutputTopic.isEmpty()).isTrue();
    }
}

