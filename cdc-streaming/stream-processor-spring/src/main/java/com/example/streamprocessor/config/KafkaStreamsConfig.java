package com.example.streamprocessor.config;

import com.example.streamprocessor.serde.EventHeaderSerde;
import org.apache.kafka.common.serialization.Serde;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.KStream;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.annotation.EnableKafkaStreams;

import java.util.List;
import java.util.function.Predicate;

/**
 * Kafka Streams configuration for event routing.
 * Dynamically loads filters from filters.yml configuration.
 */
@Configuration
@EnableKafkaStreams
public class KafkaStreamsConfig {

    private static final Logger log = LoggerFactory.getLogger(KafkaStreamsConfig.class);
    private static final String LOG_PREFIX = "[STREAM-PROCESSOR]";

    @Value("${spring.kafka.streams.source-topic}")
    private String sourceTopic;

    @Autowired(required = false)
    private FiltersConfig filtersConfig;

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

        // Apply dynamic filters from configuration
        if (filtersConfig != null && filtersConfig.getFilters() != null) {
            List<FilterConfig> filters = filtersConfig.getFilters();
            log.info("{} Loading {} filter(s) from configuration", LOG_PREFIX, filters.size());
            
            for (FilterConfig filterConfig : filters) {
                if (filterConfig == null || filterConfig.getId() == null || filterConfig.getOutputTopic() == null) {
                    log.warn("{} Skipping invalid filter configuration", LOG_PREFIX);
                    continue;
                }
                
                // Skip disabled filters
                if (filterConfig.getEnabled() != null && !filterConfig.getEnabled()) {
                    log.info("{} Skipping disabled filter: {}", LOG_PREFIX, filterConfig.getId());
                    continue;
                }
                
                // Skip deleted filters
                if ("deleted".equals(filterConfig.getStatus())) {
                    log.info("{} Skipping deleted filter: {}", LOG_PREFIX, filterConfig.getId());
                    continue;
                }
                
                // Skip pending_deletion filters
                if ("pending_deletion".equals(filterConfig.getStatus())) {
                    log.info("{} Skipping pending_deletion filter: {}", LOG_PREFIX, filterConfig.getId());
                    continue;
                }
                
                // Log warning for deprecated filters
                if ("deprecated".equals(filterConfig.getStatus())) {
                    log.warn("{} Filter {} is deprecated and may be removed soon", LOG_PREFIX, filterConfig.getId());
                }
                
                // Add -spring suffix if not already present
                final String outputTopic = filterConfig.getOutputTopic().endsWith("-spring") 
                    ? filterConfig.getOutputTopic() 
                    : filterConfig.getOutputTopic() + "-spring";
                
                log.info("{} Configuring filter: {} -> {}", LOG_PREFIX, filterConfig.getId(), outputTopic);
                
                // Create predicate from filter conditions
                final Predicate<com.example.streamprocessor.model.EventHeader> filterPredicate = 
                    FilterConditionEvaluator.createPredicate(filterConfig);
                
                // Apply filter and route to output topic
                source.filter((key, value) -> filterPredicate.test(value))
                    .peek((key, value) -> {
                        log.info("{} Event sent to {} - id={}, event_name={}, event_type={}, __op={}, __ts_ms={}",
                            LOG_PREFIX, outputTopic,
                            value != null ? value.getId() : "null",
                            value != null ? value.getEventName() : "null",
                            value != null ? value.getEventType() : "null",
                            value != null ? value.getOp() : "null",
                            value != null ? value.getTsMs() : null
                        );
                    })
                    .to(outputTopic);
            }
        } else {
            log.warn("{} No filter configuration found. Filters will not be applied.", LOG_PREFIX);
            log.warn("{} Ensure filters.yml exists in src/main/resources/", LOG_PREFIX);
        }

        return source;
    }
}
