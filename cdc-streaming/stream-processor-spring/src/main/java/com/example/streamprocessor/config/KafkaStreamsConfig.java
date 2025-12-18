package com.example.streamprocessor.config;

import com.example.streamprocessor.serde.EventHeaderSerde;
import org.apache.kafka.common.serialization.Serde;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.KStream;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
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

    private static final Logger log = LoggerFactory.getLogger(KafkaStreamsConfig.class);
    private static final String LOG_PREFIX = "[STREAM-PROCESSOR]";

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

        // Log events received from raw-event-headers topic
        source.peek((key, value) -> {
            if (value != null) {
                log.info("{} Event received from {} - id={}, event_name={}, event_type={}, __op={}, __table={}, __ts_ms={}, created_date={}, saved_date={}",
                    LOG_PREFIX, sourceTopic,
                    value.getId(),
                    value.getEventName(),
                    value.getEventType(),
                    value.getOp(),
                    value.getTable(),
                    value.getTsMs(),
                    value.getCreatedDate(),
                    value.getSavedDate()
                );
            } else {
                log.warn("{} Received null event from {} with key={}", LOG_PREFIX, sourceTopic, key);
            }
        });

        // Route to filtered-car-created-events-spring
        // Filter: event_type = 'CarCreated' AND __op = 'c'
        // Note: Spring Boot writes to -spring suffixed topics to distinguish from Flink processor
        source.filter((key, value) -> 
            value != null && 
            "CarCreated".equals(value.getEventType()) && 
            "c".equals(value.getOp())
        ).peek((key, value) -> {
            log.info("{} Event sent to filtered-car-created-events-spring - id={}, event_name={}, event_type={}, __op={}, __ts_ms={}",
                LOG_PREFIX,
                value != null ? value.getId() : "null",
                value != null ? value.getEventName() : "null",
                value != null ? value.getEventType() : "null",
                value != null ? value.getOp() : "null",
                value != null ? value.getTsMs() : null
            );
        }).to("filtered-car-created-events-spring");

        // Route to filtered-loan-created-events-spring
        // Filter: event_type = 'LoanCreated' AND __op = 'c'
        source.filter((key, value) -> 
            value != null && 
            "LoanCreated".equals(value.getEventType()) && 
            "c".equals(value.getOp())
        ).peek((key, value) -> {
            log.info("{} Event sent to filtered-loan-created-events-spring - id={}, event_name={}, event_type={}, __op={}, __ts_ms={}",
                LOG_PREFIX,
                value != null ? value.getId() : "null",
                value != null ? value.getEventName() : "null",
                value != null ? value.getEventType() : "null",
                value != null ? value.getOp() : "null",
                value != null ? value.getTsMs() : null
            );
        }).to("filtered-loan-created-events-spring");

        // Route to filtered-loan-payment-submitted-events-spring
        // Filter: event_type = 'LoanPaymentSubmitted' AND __op = 'c'
        source.filter((key, value) -> 
            value != null && 
            "LoanPaymentSubmitted".equals(value.getEventType()) && 
            "c".equals(value.getOp())
        ).peek((key, value) -> {
            log.info("{} Event sent to filtered-loan-payment-submitted-events-spring - id={}, event_name={}, event_type={}, __op={}, __ts_ms={}",
                LOG_PREFIX,
                value != null ? value.getId() : "null",
                value != null ? value.getEventName() : "null",
                value != null ? value.getEventType() : "null",
                value != null ? value.getOp() : "null",
                value != null ? value.getTsMs() : null
            );
        }).to("filtered-loan-payment-submitted-events-spring");

        // Route to filtered-service-events-spring
        // Filter: event_type = 'CarServiceDone' AND __op = 'c'
        source.filter((key, value) -> 
            value != null && 
            "CarServiceDone".equals(value.getEventType()) && 
            "c".equals(value.getOp())
        ).peek((key, value) -> {
            log.info("{} Event sent to filtered-service-events-spring - id={}, event_name={}, event_type={}, __op={}, __ts_ms={}",
                LOG_PREFIX,
                value != null ? value.getId() : "null",
                value != null ? value.getEventName() : "null",
                value != null ? value.getEventType() : "null",
                value != null ? value.getOp() : "null",
                value != null ? value.getTsMs() : null
            );
        }).to("filtered-service-events-spring");

        return source;
    }
}
