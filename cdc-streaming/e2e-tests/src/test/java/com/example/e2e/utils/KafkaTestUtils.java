package com.example.e2e.utils;

import com.example.e2e.model.EventHeader;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;
import org.apache.kafka.common.serialization.ByteArrayDeserializer;

import java.time.Duration;
import java.util.*;
import java.util.concurrent.TimeUnit;

/**
 * Utility class for Kafka operations in tests.
 */
public class KafkaTestUtils {
    
    private static final ObjectMapper objectMapper = new ObjectMapper()
            .registerModule(new JavaTimeModule())
            .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
    
    private final String bootstrapServers;
    private final String apiKey;
    private final String apiSecret;
    
    public KafkaTestUtils(String bootstrapServers, String apiKey, String apiSecret) {
        this.bootstrapServers = bootstrapServers;
        this.apiKey = apiKey;
        this.apiSecret = apiSecret;
    }
    
    /**
     * Create a Kafka producer with Confluent Cloud configuration.
     */
    private KafkaProducer<String, String> createProducer() {
        Properties props = new Properties();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.ACKS_CONFIG, "all");
        props.put(ProducerConfig.RETRIES_CONFIG, 3);
        props.put(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG, 30000);
        props.put(ProducerConfig.METADATA_MAX_AGE_CONFIG, 30000);
        
        // Confluent Cloud SASL_SSL configuration
        if (apiKey != null && !apiKey.isEmpty() && apiSecret != null && !apiSecret.isEmpty()) {
            props.put("security.protocol", "SASL_SSL");
            props.put("sasl.mechanism", "PLAIN");
            props.put("sasl.jaas.config", String.format(
                "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"%s\" password=\"%s\";",
                apiKey, apiSecret
            ));
            // SSL configuration for Confluent Cloud
            props.put("ssl.endpoint.identification.algorithm", "https");
        }
        
        return new KafkaProducer<>(props);
    }
    
    /**
     * Create a Kafka consumer with Confluent Cloud configuration.
     */
    private KafkaConsumer<String, byte[]> createConsumer(String groupId) {
        Properties props = new Properties();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, groupId);
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, ByteArrayDeserializer.class.getName());
        // Use "earliest" as fallback, but we'll seek to end to only read new messages
        // This is more reliable than "latest" which can miss messages
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "true");
        props.put(ConsumerConfig.REQUEST_TIMEOUT_MS_CONFIG, 30000);
        props.put(ConsumerConfig.METADATA_MAX_AGE_CONFIG, 30000);
        // Small max poll records to ensure we process events quickly
        props.put(ConsumerConfig.MAX_POLL_RECORDS_CONFIG, 10);
        
        // Confluent Cloud SASL_SSL configuration
        if (apiKey != null && !apiKey.isEmpty() && apiSecret != null && !apiSecret.isEmpty()) {
            props.put("security.protocol", "SASL_SSL");
            props.put("sasl.mechanism", "PLAIN");
            props.put("ssl.endpoint.identification.algorithm", "https");
            props.put("sasl.jaas.config", String.format(
                "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"%s\" password=\"%s\";",
                apiKey, apiSecret
            ));
        }
        
        return new KafkaConsumer<>(props);
    }
    
    /**
     * Strip Confluent Schema Registry header from message value.
     * Format: [magic byte (0x00)][4-byte schema ID][actual JSON payload]
     */
    private String stripSchemaRegistryHeader(byte[] value) {
        if (value == null || value.length < 5) {
            // Not a schema registry message, return as string
            return new String(value);
        }
        
        // Check for magic byte (0x00) at the start
        if (value[0] == 0x00) {
            // Skip magic byte (1 byte) + schema ID (4 bytes) = 5 bytes
            byte[] jsonBytes = Arrays.copyOfRange(value, 5, value.length);
            return new String(jsonBytes);
        }
        
        // Not a schema registry message, return as string
        return new String(value);
    }
    
    /**
     * Publish a test event to Kafka topic.
     */
    public void publishTestEvent(String topic, EventHeader event) throws Exception {
        try (KafkaProducer<String, String> producer = createProducer()) {
            String eventJson = objectMapper.writeValueAsString(event);
            ProducerRecord<String, String> record = new ProducerRecord<>(topic, event.getId(), eventJson);
            producer.send(record).get(10, TimeUnit.SECONDS);
            // Flush to ensure the record is sent immediately
            producer.flush();
        }
    }
    
    /**
     * Publish multiple test events to Kafka topic.
     */
    public void publishTestEvents(String topic, List<EventHeader> events) throws Exception {
        try (KafkaProducer<String, String> producer = createProducer()) {
            for (EventHeader event : events) {
                String eventJson = objectMapper.writeValueAsString(event);
                ProducerRecord<String, String> record = new ProducerRecord<>(topic, event.getId(), eventJson);
                producer.send(record);
            }
            producer.flush();
        }
    }
    
    /**
     * Prepare a consumer for a topic by positioning it at the end.
     * Call this BEFORE publishing events to ensure you capture them.
     * @param topic The topic to prepare for
     * @return A prepared consumer positioned at the end of the topic
     */
    public KafkaConsumer<String, byte[]> prepareConsumerForTopic(String topic) throws Exception {
        String groupId = "e2e-test-consumer-prep-" + UUID.randomUUID().toString();
        KafkaConsumer<String, byte[]> consumer = createConsumer(groupId);
        consumer.subscribe(Collections.singletonList(topic));
        
        // Wait for partition assignment
        int assignmentWaitCount = 0;
        while (consumer.assignment().isEmpty() && assignmentWaitCount < 20) {
            consumer.poll(Duration.ofMillis(200));
            assignmentWaitCount++;
        }
        
        if (consumer.assignment().isEmpty()) {
            consumer.close();
            throw new RuntimeException("Failed to get partition assignment for topic: " + topic);
        }
        
        // Seek to end of all assigned partitions to only read new messages
        consumer.seekToEnd(consumer.assignment());
        
        // Poll once to ensure we're positioned at the end
        consumer.poll(Duration.ofMillis(100));
        
        return consumer;
    }
    
    /**
     * Consume events from a Kafka topic.
     */
    public List<EventHeader> consumeEvents(String topic, int expectedCount, Duration timeout) throws Exception {
        return consumeEvents(topic, expectedCount, timeout, null);
    }
    
    /**
     * Consume events from a Kafka topic, optionally filtered by event ID prefix.
     * @param topic The topic to consume from
     * @param expectedCount Expected number of events
     * @param timeout Maximum time to wait
     * @param eventIdPrefix If provided, only consume events whose ID starts with this prefix
     */
    public List<EventHeader> consumeEvents(String topic, int expectedCount, Duration timeout, String eventIdPrefix) throws Exception {
        List<EventHeader> events = new ArrayList<>();
        String groupId = "e2e-test-consumer-" + UUID.randomUUID().toString();
        
        try (KafkaConsumer<String, byte[]> consumer = createConsumer(groupId)) {
            consumer.subscribe(Collections.singletonList(topic));
            
            // Wait for partition assignment
            int assignmentWaitCount = 0;
            while (consumer.assignment().isEmpty() && assignmentWaitCount < 20) {
                consumer.poll(Duration.ofMillis(200));
                assignmentWaitCount++;
            }
            
            if (consumer.assignment().isEmpty()) {
                throw new RuntimeException("Failed to get partition assignment for topic: " + topic);
            }
            
            // Seek to end of all assigned partitions to only read new messages
            // This ensures we don't read old events from previous test runs
            consumer.seekToEnd(consumer.assignment());
            
            // Poll once to ensure we're at the end and get current position
            consumer.poll(Duration.ofMillis(100));
            
            // Wait for Kafka Streams to process and commit events
            // Kafka Streams uses transactions which can take 5-10 seconds to become visible
            // Also account for network latency and processing time
            Thread.sleep(5000);
            
            long startTime = System.currentTimeMillis();
            long lastPollTime = startTime;
            int consecutiveEmptyPolls = 0;
            
            while (events.size() < expectedCount && (System.currentTimeMillis() - startTime) < timeout.toMillis()) {
                ConsumerRecords<String, byte[]> records = consumer.poll(Duration.ofSeconds(2));
                
                if (records.isEmpty()) {
                    consecutiveEmptyPolls++;
                    // If we've had multiple empty polls, wait a bit longer for Kafka Streams
                    if (consecutiveEmptyPolls > 3 && (System.currentTimeMillis() - lastPollTime) < 10000) {
                        Thread.sleep(2000); // Additional wait for Kafka Streams processing
                    }
                    continue;
                }
                
                consecutiveEmptyPolls = 0;
                lastPollTime = System.currentTimeMillis();
                
                for (ConsumerRecord<String, byte[]> record : records) {
                    try {
                        String jsonValue = stripSchemaRegistryHeader(record.value());
                        EventHeader event = objectMapper.readValue(jsonValue, EventHeader.class);
                        
                        // Filter by event ID prefix if provided
                        if (eventIdPrefix == null || (event.getId() != null && event.getId().startsWith(eventIdPrefix))) {
                            events.add(event);
                        }
                    } catch (Exception e) {
                        // Skip malformed events, but log for debugging
                        System.err.println("Failed to parse event from topic " + topic + ": " + e.getMessage());
                    }
                }
                
                // If we found events matching our prefix, we can break early if we have enough
                if (events.size() >= expectedCount) {
                    break;
                }
            }
        }
        
        return events;
    }
    
    /**
     * Consume events using a pre-positioned consumer.
     * Use this when you've already positioned the consumer before publishing events.
     */
    public List<EventHeader> consumeEventsWithConsumer(KafkaConsumer<String, byte[]> consumer, int expectedCount, Duration timeout, String eventIdPrefix) throws Exception {
        List<EventHeader> events = new ArrayList<>();
        
        // Wait for Kafka Streams to process and commit events
        // Kafka Streams uses transactions which can take 5-10 seconds to become visible
        Thread.sleep(5000);
        
        long startTime = System.currentTimeMillis();
        long lastPollTime = startTime;
        int consecutiveEmptyPolls = 0;
        
        while (events.size() < expectedCount && (System.currentTimeMillis() - startTime) < timeout.toMillis()) {
            ConsumerRecords<String, byte[]> records = consumer.poll(Duration.ofSeconds(2));
            
            if (records.isEmpty()) {
                consecutiveEmptyPolls++;
                // If we've had multiple empty polls, wait a bit longer for Kafka Streams
                if (consecutiveEmptyPolls > 3 && (System.currentTimeMillis() - lastPollTime) < 10000) {
                    Thread.sleep(2000); // Additional wait for Kafka Streams processing
                }
                continue;
            }
            
            consecutiveEmptyPolls = 0;
            lastPollTime = System.currentTimeMillis();
            
            for (ConsumerRecord<String, byte[]> record : records) {
                try {
                    String jsonValue = stripSchemaRegistryHeader(record.value());
                    EventHeader event = objectMapper.readValue(jsonValue, EventHeader.class);
                    
                    // Filter by event ID prefix if provided
                    if (eventIdPrefix == null || (event.getId() != null && event.getId().startsWith(eventIdPrefix))) {
                        events.add(event);
                    }
                } catch (Exception e) {
                    // Skip malformed events, but log for debugging
                    System.err.println("Failed to parse event: " + e.getMessage());
                }
            }
            
            // If we found events matching our prefix, we can break early if we have enough
            if (events.size() >= expectedCount) {
                break;
            }
        }
        
        return events;
    }
    
    /**
     * Consume all available events from a topic (up to maxCount).
     */
    public List<EventHeader> consumeAllEvents(String topic, int maxCount, Duration timeout) throws Exception {
        List<EventHeader> events = new ArrayList<>();
        String groupId = "e2e-test-consumer-all-" + UUID.randomUUID().toString();
        
        try (KafkaConsumer<String, byte[]> consumer = createConsumer(groupId)) {
            consumer.subscribe(Collections.singletonList(topic));
            
            long startTime = System.currentTimeMillis();
            long lastRecordTime = startTime;
            
            while ((System.currentTimeMillis() - startTime) < timeout.toMillis() && 
                   (System.currentTimeMillis() - lastRecordTime) < 5000) { // 5 seconds without new records
                ConsumerRecords<String, byte[]> records = consumer.poll(Duration.ofSeconds(1));
                if (records.isEmpty()) {
                    continue;
                }
                
                for (ConsumerRecord<String, byte[]> record : records) {
                    String jsonValue = stripSchemaRegistryHeader(record.value());
                    EventHeader event = objectMapper.readValue(jsonValue, EventHeader.class);
                    events.add(event);
                    lastRecordTime = System.currentTimeMillis();
                    
                    if (events.size() >= maxCount) {
                        return events;
                    }
                }
            }
        }
        
        return events;
    }
    
    /**
     * Wait for a topic to be available (by attempting to consume).
     */
    public boolean waitForTopic(String topic, Duration timeout) {
        String groupId = "e2e-test-wait-" + UUID.randomUUID().toString();
        try (KafkaConsumer<String, byte[]> consumer = createConsumer(groupId)) {
            consumer.subscribe(Collections.singletonList(topic));
            long startTime = System.currentTimeMillis();
            
            while ((System.currentTimeMillis() - startTime) < timeout.toMillis()) {
                consumer.poll(Duration.ofSeconds(1));
                Set<String> topics = consumer.listTopics().keySet();
                if (topics.contains(topic)) {
                    return true;
                }
            }
        } catch (Exception e) {
            // Topic might not exist yet
        }
        return false;
    }
    
    /**
     * Get approximate message count in a topic (by consuming with a new consumer group).
     */
    public int getTopicMessageCount(String topic, Duration timeout) throws Exception {
        List<EventHeader> events = consumeAllEvents(topic, Integer.MAX_VALUE, timeout);
        return events.size();
    }
    
    /**
     * Reset consumer group offsets to earliest.
     */
    public void resetConsumerGroup(String groupId, String topic) {
        // Note: This is a simplified implementation
        // In production, you might use AdminClient to reset offsets
        try (KafkaConsumer<String, byte[]> consumer = createConsumer(groupId + "-reset")) {
            consumer.subscribe(Collections.singletonList(topic));
            consumer.poll(Duration.ofSeconds(1));
            consumer.seekToBeginning(consumer.assignment());
        }
    }
}
