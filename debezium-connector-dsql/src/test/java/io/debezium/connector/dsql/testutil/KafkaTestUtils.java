package io.debezium.connector.dsql.testutil;

import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.common.serialization.StringDeserializer;

import java.time.Duration;
import java.util.*;
import java.util.stream.Collectors;

/**
 * Kafka test utilities for E2E tests.
 */
public class KafkaTestUtils {
    
    /**
     * Create a Kafka consumer for testing.
     */
    public static KafkaConsumer<String, String> createConsumer(String bootstrapServers, String groupId) {
        Properties props = new Properties();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, groupId);
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "false");
        
        return new KafkaConsumer<>(props);
    }
    
    /**
     * Consume records from a topic until timeout or expected count is reached.
     */
    public static List<ConsumerRecord<String, String>> consumeRecords(
            KafkaConsumer<String, String> consumer, 
            String topic, 
            int expectedCount, 
            long timeoutMs) {
        
        consumer.subscribe(Collections.singletonList(topic));
        List<ConsumerRecord<String, String>> records = new ArrayList<>();
        long startTime = System.currentTimeMillis();
        
        while (records.size() < expectedCount && (System.currentTimeMillis() - startTime) < timeoutMs) {
            var polled = consumer.poll(Duration.ofMillis(1000));
            polled.forEach(records::add);
        }
        
        return records;
    }
    
    /**
     * Consume all available records from a topic within timeout.
     */
    public static List<ConsumerRecord<String, String>> consumeAllRecords(
            KafkaConsumer<String, String> consumer, 
            String topic, 
            long timeoutMs) {
        
        consumer.subscribe(Collections.singletonList(topic));
        List<ConsumerRecord<String, String>> records = new ArrayList<>();
        long startTime = System.currentTimeMillis();
        int emptyPolls = 0;
        
        while ((System.currentTimeMillis() - startTime) < timeoutMs && emptyPolls < 3) {
            var polled = consumer.poll(Duration.ofMillis(1000));
            if (polled.isEmpty()) {
                emptyPolls++;
            } else {
                emptyPolls = 0;
                polled.forEach(records::add);
            }
        }
        
        return records;
    }
    
    /**
     * Get record values as strings.
     */
    public static List<String> getRecordValues(List<ConsumerRecord<String, String>> records) {
        return records.stream()
                .map(ConsumerRecord::value)
                .collect(Collectors.toList());
    }
    
    /**
     * Get record keys as strings.
     */
    public static List<String> getRecordKeys(List<ConsumerRecord<String, String>> records) {
        return records.stream()
                .map(ConsumerRecord::key)
                .filter(Objects::nonNull)
                .collect(Collectors.toList());
    }
}
