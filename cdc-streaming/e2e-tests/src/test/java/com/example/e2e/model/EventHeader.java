package com.example.e2e.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * EventHeader model matching the structure from raw-event-headers topic.
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
    private String headerData;
    
    @JsonProperty("__op")
    private String op;
    
    @JsonProperty("__table")
    private String table;
    
    @JsonProperty("__ts_ms")
    private Long tsMs;
}

