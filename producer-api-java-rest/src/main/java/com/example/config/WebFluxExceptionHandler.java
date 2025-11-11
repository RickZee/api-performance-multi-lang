package com.example.config;

import lombok.extern.slf4j.Slf4j;
import org.springframework.core.annotation.Order;
import org.springframework.core.codec.DecodingException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.support.WebExchangeBindException;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.web.server.ServerWebInputException;
import org.springframework.web.server.WebExceptionHandler;
import reactor.core.publisher.Mono;

import java.nio.charset.StandardCharsets;

@Component
@Order(-3) // Higher priority than default handlers (lower number = higher priority)
@Slf4j
public class WebFluxExceptionHandler implements WebExceptionHandler {

    @Override
    public Mono<Void> handle(ServerWebExchange exchange, Throwable ex) {
        if (ex instanceof WebExchangeBindException) {
            WebExchangeBindException bindEx = (WebExchangeBindException) ex;
            log.warn("Validation error: {}", bindEx.getMessage());
            String errors = bindEx.getBindingResult().getFieldErrors().stream()
                    .map(error -> error.getField() + ": " + error.getDefaultMessage())
                    .reduce((a, b) -> a + ", " + b)
                    .orElse("Validation failed");
            
            exchange.getResponse().setStatusCode(HttpStatus.UNPROCESSABLE_ENTITY);
            exchange.getResponse().getHeaders().add("Content-Type", "text/plain;charset=UTF-8");
            String body = "Validation failed: " + errors;
            var buffer = exchange.getResponse().bufferFactory().wrap(body.getBytes(StandardCharsets.UTF_8));
            return exchange.getResponse().writeWith(Mono.just(buffer));
        }
        
        if (ex instanceof ServerWebInputException) {
            ServerWebInputException inputEx = (ServerWebInputException) ex;
            log.warn("WebFluxExceptionHandler caught ServerWebInputException: {} - Status: {}", inputEx.getMessage(), inputEx.getStatusCode());
            // Return 422 for all BAD_REQUEST ServerWebInputException cases (validation/deserialization issues)
            // Check if response is already committed
            if (exchange.getResponse().isCommitted()) {
                return Mono.error(ex);
            }
            
            exchange.getResponse().setStatusCode(HttpStatus.UNPROCESSABLE_ENTITY);
            exchange.getResponse().getHeaders().set("Content-Type", "text/plain;charset=UTF-8");
            String body = "Invalid request: " + (inputEx.getMessage() != null ? inputEx.getMessage() : "Unknown error");
            var buffer = exchange.getResponse().bufferFactory().wrap(body.getBytes(StandardCharsets.UTF_8));
            return exchange.getResponse().writeWith(Mono.just(buffer));
        }
        
        if (ex instanceof DecodingException) {
            log.warn("Decoding error: {}", ex.getMessage());
            exchange.getResponse().setStatusCode(HttpStatus.UNPROCESSABLE_ENTITY);
            exchange.getResponse().getHeaders().add("Content-Type", "text/plain;charset=UTF-8");
            String body = "Invalid request: Failed to parse request body";
            var buffer = exchange.getResponse().bufferFactory().wrap(body.getBytes(StandardCharsets.UTF_8));
            return exchange.getResponse().writeWith(Mono.just(buffer));
        }
        
        // Let other handlers process it
        return Mono.error(ex);
    }
}

