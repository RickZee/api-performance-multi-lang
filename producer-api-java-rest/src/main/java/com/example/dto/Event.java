package com.example.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.NotEmpty;

import java.util.List;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class Event {

    @NotNull(message = "eventHeader is required")
    @Valid
    private EventHeader eventHeader;

    @NotEmpty(message = "entities is required and cannot be empty")
    @Valid
    private List<Entity> entities;
}
