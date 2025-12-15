package com.example.streamprocessor.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * EventHeader model matching the structure from raw-event-headers topic.
 * 
 * Structure from Flink SQL:
 * - id, event_name, event_type, created_date, saved_date, header_data (JSON string), __op, __table, __ts_ms
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class EventHeader {
    
    @JsonProperty("id")
    private String id;
    
    @JsonProperty("event_name")
    private String eventName;
    
    @JsonProperty("event_type")
    private String eventType;
    
    @JsonProperty("created_date")
    private String createdDate;
    
    @JsonProperty("saved_date")
    private String savedDate;
    
    @JsonProperty("header_data")
    private String headerData; // JSON string containing event header structure
    
    @JsonProperty("__op")
    private String op; // CDC operation: 'c'=create, 'u'=update, 'd'=delete
    
    @JsonProperty("__table")
    private String table; // Source table name
    
    @JsonProperty("__ts_ms")
    private Long tsMs; // CDC timestamp in milliseconds
}

