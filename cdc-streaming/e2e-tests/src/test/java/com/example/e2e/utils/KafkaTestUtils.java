package com.example.e2e.utils;

import com.example.e2e.model.EventHeader;
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

import java.time.Duration;
import java.util.*;
import java.util.concurrent.TimeUnit;

/**
 * Utility class for Kafka operations in tests.
 */
public class KafkaTestUtils {
    
    private static final ObjectMapper objectMapper = new ObjectMapper()
            .registerModule(new JavaTimeModule());
    
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
        
        // Confluent Cloud SASL_SSL configuration
        if (apiKey != null && !apiKey.isEmpty() && apiSecret != null && !apiSecret.isEmpty()) {
            props.put("security.protocol", "SASL_SSL");
            props.put("sasl.mechanism", "PLAIN");
            props.put("sasl.jaas.config", String.format(
                "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"%s\" password=\"%s\";",
                apiKey, apiSecret
            ));
        }
        
        return new KafkaProducer<>(props);
    }
    
    /**
     * Create a Kafka consumer with Confluent Cloud configuration.
     */
    private KafkaConsumer<String, String> createConsumer(String groupId) {
        Properties props = new Properties();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, groupId);
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "true");
        
        // Confluent Cloud SASL_SSL configuration
        if (apiKey != null && !apiKey.isEmpty() && apiSecret != null && !apiSecret.isEmpty()) {
            props.put("security.protocol", "SASL_SSL");
            props.put("sasl.mechanism", "PLAIN");
            props.put("sasl.jaas.config", String.format(
                "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"%s\" password=\"%s\";",
                apiKey, apiSecret
            ));
        }
        
        return new KafkaConsumer<>(props);
    }
    
    /**
     * Publish a test event to Kafka topic.
     */
    public void publishTestEvent(String topic, EventHeader event) throws Exception {
        try (KafkaProducer<String, String> producer = createProducer()) {
            String eventJson = objectMapper.writeValueAsString(event);
            ProducerRecord<String, String> record = new ProducerRecord<>(topic, event.getId(), eventJson);
            producer.send(record).get(10, TimeUnit.SECONDS);
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
     * Consume events from a Kafka topic.
     */
    public List<EventHeader> consumeEvents(String topic, int expectedCount, Duration timeout) throws Exception {
        List<EventHeader> events = new ArrayList<>();
        String groupId = "e2e-test-consumer-" + UUID.randomUUID().toString();
        
        try (KafkaConsumer<String, String> consumer = createConsumer(groupId)) {
            consumer.subscribe(Collections.singletonList(topic));
            
            long startTime = System.currentTimeMillis();
            while (events.size() < expectedCount && (System.currentTimeMillis() - startTime) < timeout.toMillis()) {
                ConsumerRecords<String, String> records = consumer.poll(Duration.ofSeconds(1));
                for (ConsumerRecord<String, String> record : records) {
                    EventHeader event = objectMapper.readValue(record.value(), EventHeader.class);
                    events.add(event);
                }
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
        
        try (KafkaConsumer<String, String> consumer = createConsumer(groupId)) {
            consumer.subscribe(Collections.singletonList(topic));
            
            long startTime = System.currentTimeMillis();
            long lastRecordTime = startTime;
            
            while ((System.currentTimeMillis() - startTime) < timeout.toMillis() && 
                   (System.currentTimeMillis() - lastRecordTime) < 5000) { // 5 seconds without new records
                ConsumerRecords<String, String> records = consumer.poll(Duration.ofSeconds(1));
                if (records.isEmpty()) {
                    continue;
                }
                
                for (ConsumerRecord<String, String> record : records) {
                    EventHeader event = objectMapper.readValue(record.value(), EventHeader.class);
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
        try (KafkaConsumer<String, String> consumer = createConsumer(groupId)) {
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
        try (KafkaConsumer<String, String> consumer = createConsumer(groupId + "-reset")) {
            consumer.subscribe(Collections.singletonList(topic));
            consumer.poll(Duration.ofSeconds(1));
            consumer.seekToBeginning(consumer.assignment());
        }
    }
}
