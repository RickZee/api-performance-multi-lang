package com.example.metadata.controller;

import com.example.metadata.model.HealthResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.reactive.server.WebTestClient;

import static org.junit.jupiter.api.Assertions.*;

class HealthControllerTest {
    
    private WebTestClient webTestClient;
    
    @BeforeEach
    void setUp() {
        webTestClient = WebTestClient.bindToController(new HealthController()).build();
    }
    
    @Test
    void testHealth() {
        webTestClient.get()
            .uri("/api/v1/health")
            .exchange()
            .expectStatus().isOk()
            .expectBody(HealthResponse.class)
            .value(response -> {
                assertEquals("healthy", response.getStatus());
                assertEquals("v1", response.getVersion());
            });
    }
}
