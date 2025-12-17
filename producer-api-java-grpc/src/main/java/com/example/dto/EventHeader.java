package com.example.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.OffsetDateTime;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class EventHeader {
    private String uuid;
    private String eventName;
    private OffsetDateTime createdDate;
    private OffsetDateTime savedDate;
    private String eventType;
}
