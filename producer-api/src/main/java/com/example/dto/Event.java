package com.example.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class Event {

    @NotNull(message = "eventHeader is required")
    @Valid
    private EventHeader eventHeader;

    @Valid
    private EventBody eventBody;
}
