package com.example.streamprocessor.serde;

import com.example.streamprocessor.model.EventHeader;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.apache.kafka.common.serialization.Deserializer;
import org.apache.kafka.common.serialization.Serde;
import org.apache.kafka.common.serialization.Serializer;

import java.io.IOException;
import java.util.Map;

/**
 * Custom Serde for EventHeader JSON serialization/deserialization.
 */
public class EventHeaderSerde implements Serde<EventHeader> {

    private final ObjectMapper objectMapper;

    public EventHeaderSerde() {
        this.objectMapper = new ObjectMapper();
        this.objectMapper.registerModule(new JavaTimeModule());
    }

    @Override
    public Serializer<EventHeader> serializer() {
        return new EventHeaderSerializer();
    }

    @Override
    public Deserializer<EventHeader> deserializer() {
        return new EventHeaderDeserializer();
    }

    @Override
    public void configure(Map<String, ?> configs, boolean isKey) {
        // No additional configuration needed
    }

    @Override
    public void close() {
        // No resources to close
    }

    private class EventHeaderSerializer implements Serializer<EventHeader> {
        @Override
        public byte[] serialize(String topic, EventHeader data) {
            if (data == null) {
                return null;
            }
            try {
                return objectMapper.writeValueAsBytes(data);
            } catch (IOException e) {
                throw new RuntimeException("Error serializing EventHeader", e);
            }
        }

        @Override
        public void close() {
            // No resources to close
        }
    }

    private class EventHeaderDeserializer implements Deserializer<EventHeader> {
        @Override
        public EventHeader deserialize(String topic, byte[] data) {
            if (data == null) {
                return null;
            }
            try {
                return objectMapper.readValue(data, EventHeader.class);
            } catch (IOException e) {
                throw new RuntimeException("Error deserializing EventHeader", e);
            }
        }

        @Override
        public void close() {
            // No resources to close
        }
    }
}

