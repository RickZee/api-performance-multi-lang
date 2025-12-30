package com.example.streamprocessor.config;

import com.example.streamprocessor.model.EventHeader;
import com.example.streamprocessor.service.DynamicFilterLoaderService;
import com.example.streamprocessor.service.DynamicFilterManager;
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

import jakarta.annotation.PostConstruct;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Set;

/**
 * Kafka Streams configuration for event routing.
 * Supports both static filters from filters.yml and dynamic filters from Metadata Service.
 */
@Configuration
@EnableKafkaStreams
public class KafkaStreamsConfig {

    private static final Logger log = LoggerFactory.getLogger(KafkaStreamsConfig.class);
    private static final String LOG_PREFIX = "[STREAM-PROCESSOR]";

    @Value("${spring.kafka.streams.source-topic}")
    private String sourceTopic;

    @Value("${app.display-timezone:America/New_York}")
    private String displayTimezone;

    @Autowired(required = false)
    private FiltersConfig filtersConfig;
    
    @Autowired(required = false)
    private DynamicFilterLoaderService dynamicFilterLoaderService;
    
    @Autowired(required = false)
    private DynamicFilterManager dynamicFilterManager;

    private final Serde<String> stringSerde = Serdes.String();
    private final Serde<EventHeader> eventHeaderSerde = new EventHeaderSerde();
    private static final DateTimeFormatter LOCAL_TIME_FORMATTER = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss zzz");

    @PostConstruct
    public void initialize() {
        // Register filter change listener if dynamic loading is enabled
        if (dynamicFilterLoaderService != null && dynamicFilterManager != null) {
            dynamicFilterLoaderService.addFilterChangeListener(filters -> {
                log.info("{} Filter changes detected, updating filter manager", LOG_PREFIX);
                dynamicFilterManager.updateFilters(filters);
            });
            
            // Initial load of filters into manager
            List<com.example.streamprocessor.config.FilterConfig> currentFilters = 
                    dynamicFilterLoaderService.getCurrentFilters();
            if (!currentFilters.isEmpty()) {
                log.info("{} Loading {} filters from Metadata Service into filter manager", 
                        LOG_PREFIX, currentFilters.size());
                dynamicFilterManager.updateFilters(currentFilters);
            }
        }
    }

    /**
     * Format epoch milliseconds to local time display string.
     */
    private String formatTimestamp(Long tsMs) {
        if (tsMs == null) {
            return "null";
        }
        try {
            Instant instant = Instant.ofEpochMilli(tsMs);
            ZonedDateTime zonedDateTime = instant.atZone(ZoneId.of(displayTimezone));
            String localTime = zonedDateTime.format(LOCAL_TIME_FORMATTER);
            return String.format("%d (%s)", tsMs, localTime);
        } catch (Exception e) {
            log.warn("{} Failed to format timestamp {}: {}", LOG_PREFIX, tsMs, e.getMessage());
            return String.valueOf(tsMs);
        }
    }

    /**
     * Format ISO 8601 UTC timestamp string to local time display string.
     */
    private String formatTimestampString(String utcTimestamp) {
        if (utcTimestamp == null || utcTimestamp.isEmpty() || "Unknown".equals(utcTimestamp)) {
            return utcTimestamp;
        }
        try {
            Instant instant = Instant.parse(utcTimestamp.replace("Z", "+00:00"));
            ZonedDateTime zonedDateTime = instant.atZone(ZoneId.of(displayTimezone));
            String localTime = zonedDateTime.format(LOCAL_TIME_FORMATTER);
            return String.format("%s (Local: %s)", utcTimestamp, localTime);
        } catch (Exception e) {
            log.warn("{} Failed to format timestamp string {}: {}", LOG_PREFIX, utcTimestamp, e.getMessage());
            return utcTimestamp;
        }
    }

    @Bean
    public KStream<String, EventHeader> eventRoutingStream(StreamsBuilder builder) {
        // Create source stream from raw-event-headers topic
        KStream<String, EventHeader> source = builder.stream(
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
                    formatTimestamp(value.getTsMs()),
                    formatTimestampString(value.getCreatedDate()),
                    formatTimestampString(value.getSavedDate())
                );
            } else {
                log.warn("{} Received null event from {} with key={}", LOG_PREFIX, sourceTopic, key);
            }
        });

        // Apply filters - use dynamic filters if available, otherwise fall back to static filters
        if (dynamicFilterManager != null) {
            // Use dynamic filter manager for runtime filter updates
            applyDynamicFilters(source);
        } else if (filtersConfig != null && filtersConfig.getFilters() != null) {
            // Fall back to static filters from filters.yml
            applyStaticFilters(source);
        } else {
            log.warn("{} No filter configuration found. Filters will not be applied.", LOG_PREFIX);
            log.warn("{} Ensure filters.yml exists or enable Metadata Service integration", LOG_PREFIX);
        }

        return source;
    }
    
    /**
     * Apply dynamic filters using DynamicFilterManager.
     * Filters can be updated at runtime without restart.
     */
    private void applyDynamicFilters(KStream<String, EventHeader> source) {
        log.info("{} Using dynamic filter manager for event routing", LOG_PREFIX);
        
        // Get all output topics
        Set<String> outputTopics = dynamicFilterManager.getOutputTopics();
        
        if (outputTopics.isEmpty()) {
            log.warn("{} No active filters found in dynamic filter manager", LOG_PREFIX);
            return;
        }
        
        log.info("{} Routing events to {} output topics using dynamic filters", LOG_PREFIX, outputTopics.size());
        
        // For each output topic, create a filtered stream
        for (String outputTopic : outputTopics) {
            final String topic = outputTopic;
            
            source.filter((key, value) -> {
                if (value == null) {
                    return false;
                }
                
                // Check if event matches any filter for this topic
                Set<String> matchingTopics = dynamicFilterManager.getOutputTopicsForEvent(value);
                return matchingTopics.contains(topic);
            })
            .peek((key, value) -> {
                log.info("{} Event sent to {} - id={}, event_name={}, event_type={}, __op={}, __ts_ms={}",
                    LOG_PREFIX, topic,
                    value != null ? value.getId() : "null",
                    value != null ? value.getEventName() : "null",
                    value != null ? value.getEventType() : "null",
                    value != null ? value.getOp() : "null",
                    value != null ? formatTimestamp(value.getTsMs()) : "null"
                );
            })
            .to(topic);
        }
    }
    
    /**
     * Apply static filters from filters.yml configuration.
     * Used as fallback when dynamic filter loading is disabled.
     */
    private void applyStaticFilters(KStream<String, EventHeader> source) {
        List<FilterConfig> filters = filtersConfig.getFilters();
        log.info("{} Loading {} filter(s) from static configuration", LOG_PREFIX, filters.size());
        
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
            final java.util.function.Predicate<EventHeader> filterPredicate = 
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
                        value != null ? formatTimestamp(value.getTsMs()) : "null"
                    );
                })
                .to(outputTopic);
        }
    }
}
