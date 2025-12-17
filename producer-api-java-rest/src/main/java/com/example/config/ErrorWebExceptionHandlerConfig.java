package com.example.config;

import org.springframework.boot.web.reactive.error.ErrorWebExceptionHandler;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.core.codec.DecodingException;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.support.WebExchangeBindException;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.web.server.ServerWebInputException;
import reactor.core.publisher.Mono;

import java.nio.charset.StandardCharsets;

@Configuration
public class ErrorWebExceptionHandlerConfig {

    @Bean
    @Order(-2)
    public ErrorWebExceptionHandler customErrorWebExceptionHandler() {
        return (ServerWebExchange exchange, Throwable ex) -> {
            // Check if response is already committed
            if (exchange.getResponse().isCommitted()) {
                return Mono.error(ex);
            }
            
            if (ex instanceof WebExchangeBindException) {
                WebExchangeBindException bindEx = (WebExchangeBindException) ex;
                String errors = bindEx.getBindingResult().getFieldErrors().stream()
                        .map(error -> error.getField() + ": " + error.getDefaultMessage())
                        .reduce((a, b) -> a + ", " + b)
                        .orElse("Validation failed");
                
                exchange.getResponse().setStatusCode(HttpStatus.UNPROCESSABLE_ENTITY);
                exchange.getResponse().getHeaders().setContentType(MediaType.TEXT_PLAIN);
                String body = "Validation failed: " + errors;
                var buffer = exchange.getResponse().bufferFactory().wrap(body.getBytes(StandardCharsets.UTF_8));
                return exchange.getResponse().writeWith(Mono.just(buffer));
            }
            
            if (ex instanceof ServerWebInputException) {
                ServerWebInputException inputEx = (ServerWebInputException) ex;
                // Always return 422 for ServerWebInputException (validation/deserialization issues)
                // Reset the response status before setting new one
                exchange.getResponse().setStatusCode(null);
                exchange.getResponse().setStatusCode(HttpStatus.UNPROCESSABLE_ENTITY);
                exchange.getResponse().getHeaders().setContentType(MediaType.TEXT_PLAIN);
                String body = "Invalid request: " + (inputEx.getMessage() != null ? inputEx.getMessage() : "Unknown error");
                var buffer = exchange.getResponse().bufferFactory().wrap(body.getBytes(StandardCharsets.UTF_8));
                return exchange.getResponse().writeWith(Mono.just(buffer));
            }
            
            if (ex instanceof DecodingException) {
                exchange.getResponse().setStatusCode(HttpStatus.UNPROCESSABLE_ENTITY);
                exchange.getResponse().getHeaders().setContentType(MediaType.TEXT_PLAIN);
                String body = "Invalid request: Failed to parse request body";
                var buffer = exchange.getResponse().bufferFactory().wrap(body.getBytes(StandardCharsets.UTF_8));
                return exchange.getResponse().writeWith(Mono.just(buffer));
            }
            
            return Mono.error(ex);
        };
    }
}
