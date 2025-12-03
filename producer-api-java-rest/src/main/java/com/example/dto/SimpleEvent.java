package com.example.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.constraints.NotBlank;
import java.time.OffsetDateTime;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class SimpleEvent {

    @NotBlank(message = "uuid is required")
    private String uuid;

    @NotBlank(message = "eventName is required")
    private String eventName;

    private OffsetDateTime createdDate;

    private OffsetDateTime savedDate;

    private String eventType;
}


