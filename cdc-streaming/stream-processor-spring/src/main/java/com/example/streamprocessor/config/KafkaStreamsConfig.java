package com.example.streamprocessor.config;

import com.example.streamprocessor.serde.EventHeaderSerde;
import org.apache.kafka.common.serialization.Serde;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.KStream;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.annotation.EnableKafkaStreams;

/**
 * Kafka Streams configuration for event routing.
 */
@Configuration
@EnableKafkaStreams
public class KafkaStreamsConfig {

    @Value("${spring.kafka.streams.source-topic}")
    private String sourceTopic;

    private final Serde<String> stringSerde = Serdes.String();
    private final Serde<com.example.streamprocessor.model.EventHeader> eventHeaderSerde = new EventHeaderSerde();

    @Bean
    public KStream<String, com.example.streamprocessor.model.EventHeader> eventRoutingStream(StreamsBuilder builder) {
        // Create source stream from raw-event-headers topic
        KStream<String, com.example.streamprocessor.model.EventHeader> source = builder.stream(
            sourceTopic,
            Consumed.with(stringSerde, eventHeaderSerde)
        );

        // Route to filtered-car-created-events
        // Filter: event_type = 'CarCreated' AND __op = 'c'
        source.filter((key, value) -> 
            value != null && 
            "CarCreated".equals(value.getEventType()) && 
            "c".equals(value.getOp())
        ).to("filtered-car-created-events");

        // Route to filtered-loan-created-events
        // Filter: event_type = 'LoanCreated' AND __op = 'c'
        source.filter((key, value) -> 
            value != null && 
            "LoanCreated".equals(value.getEventType()) && 
            "c".equals(value.getOp())
        ).to("filtered-loan-created-events");

        // Route to filtered-loan-payment-submitted-events
        // Filter: event_type = 'LoanPaymentSubmitted' AND __op = 'c'
        source.filter((key, value) -> 
            value != null && 
            "LoanPaymentSubmitted".equals(value.getEventType()) && 
            "c".equals(value.getOp())
        ).to("filtered-loan-payment-submitted-events");

        // Route to filtered-service-events
        // Filter: event_name = 'CarServiceDone' (note: using event_name, not event_type)
        source.filter((key, value) -> 
            value != null && 
            "CarServiceDone".equals(value.getEventName())
        ).to("filtered-service-events");

        return source;
    }
}

