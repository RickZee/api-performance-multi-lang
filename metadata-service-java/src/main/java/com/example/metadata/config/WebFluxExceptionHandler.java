package com.example.metadata.config;

import com.fasterxml.jackson.core.JsonParseException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.annotation.Order;
import org.springframework.core.codec.DecodingException;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.support.WebExchangeBindException;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.web.server.ServerWebInputException;
import org.springframework.web.server.WebExceptionHandler;
import reactor.core.publisher.Mono;

import java.nio.charset.StandardCharsets;

@Component
@Order(-2) // Higher priority than default handlers (lower number = higher priority)
@Slf4j
public class WebFluxExceptionHandler implements WebExceptionHandler {

    @Override
    public Mono<Void> handle(ServerWebExchange exchange, Throwable ex) {
        // Check if response is already committed
        if (exchange.getResponse().isCommitted()) {
            return Mono.error(ex);
        }
        
        // Handle method not allowed - check by class name since it might not be available in all Spring versions
        String className = ex.getClass().getName();
        if (className.contains("MethodNotAllowed") || 
            (ex.getMessage() != null && ex.getMessage().contains("Method") && ex.getMessage().contains("not allowed"))) {
            log.warn("Method not allowed: {}", ex.getMessage());
            exchange.getResponse().setStatusCode(HttpStatus.METHOD_NOT_ALLOWED);
            exchange.getResponse().getHeaders().setContentType(MediaType.APPLICATION_JSON);
            String body = "{\"error\":\"Method not allowed\",\"message\":\"" + 
                (ex.getMessage() != null ? escapeJson(ex.getMessage()) : "HTTP method not allowed for this endpoint") + "\"}";
            var buffer = exchange.getResponse().bufferFactory().wrap(body.getBytes(StandardCharsets.UTF_8));
            return exchange.getResponse().writeWith(Mono.just(buffer));
        }
        
        // Handle unsupported media type
        if (className.contains("UnsupportedMediaType") || 
            (ex.getMessage() != null && ex.getMessage().contains("Content type") && ex.getMessage().contains("not supported"))) {
            log.warn("Unsupported media type: {}", ex.getMessage());
            exchange.getResponse().setStatusCode(HttpStatus.BAD_REQUEST);
            exchange.getResponse().getHeaders().setContentType(MediaType.APPLICATION_JSON);
            String body = "{\"error\":\"Unsupported media type\",\"message\":\"" + 
                (ex.getMessage() != null ? escapeJson(ex.getMessage()) : "Content type not supported") + "\"}";
            var buffer = exchange.getResponse().bufferFactory().wrap(body.getBytes(StandardCharsets.UTF_8));
            return exchange.getResponse().writeWith(Mono.just(buffer));
        }
        
        if (ex instanceof ServerWebInputException) {
            ServerWebInputException inputEx = (ServerWebInputException) ex;
            log.warn("Invalid request: {}", inputEx.getMessage());
            exchange.getResponse().setStatusCode(HttpStatus.BAD_REQUEST);
            exchange.getResponse().getHeaders().setContentType(MediaType.APPLICATION_JSON);
            String body = "{\"error\":\"Invalid request\",\"message\":\"" + 
                (inputEx.getMessage() != null ? escapeJson(inputEx.getMessage()) : "Unknown error") + "\"}";
            var buffer = exchange.getResponse().bufferFactory().wrap(body.getBytes(StandardCharsets.UTF_8));
            return exchange.getResponse().writeWith(Mono.just(buffer));
        }
        
        if (ex instanceof DecodingException) {
            log.warn("Decoding error: {}", ex.getMessage());
            exchange.getResponse().setStatusCode(HttpStatus.BAD_REQUEST);
            exchange.getResponse().getHeaders().setContentType(MediaType.APPLICATION_JSON);
            String body = "{\"error\":\"Invalid request format\",\"message\":\"Failed to parse request body\"}";
            var buffer = exchange.getResponse().bufferFactory().wrap(body.getBytes(StandardCharsets.UTF_8));
            return exchange.getResponse().writeWith(Mono.just(buffer));
        }
        
        // Handle Jackson JSON parsing errors
        if (ex instanceof JsonParseException || 
            (ex.getCause() != null && ex.getCause() instanceof JsonParseException)) {
            log.warn("JSON parse error: {}", ex.getMessage());
            exchange.getResponse().setStatusCode(HttpStatus.BAD_REQUEST);
            exchange.getResponse().getHeaders().setContentType(MediaType.APPLICATION_JSON);
            String body = "{\"error\":\"Invalid JSON\",\"message\":\"Failed to parse JSON request body\"}";
            var buffer = exchange.getResponse().bufferFactory().wrap(body.getBytes(StandardCharsets.UTF_8));
            return exchange.getResponse().writeWith(Mono.just(buffer));
        }
        
        // Handle any exception that indicates JSON/parsing issues - check before other handlers
        String message = ex.getMessage();
        Throwable cause = ex.getCause();
        if (message != null && (
            className.contains("Json") ||
            className.contains("Parse") ||
            className.contains("Decode") ||
            className.contains("Codec") ||
            (cause != null && (cause.getClass().getName().contains("Json") || 
                              cause.getClass().getName().contains("Parse"))) ||
            message.contains("JSON") ||
            message.contains("parse") ||
            message.contains("decode") ||
            message.contains("Content-Type") ||
            message.contains("media type")
        )) {
            log.warn("Request parsing error: {}", ex.getMessage());
            exchange.getResponse().setStatusCode(HttpStatus.BAD_REQUEST);
            exchange.getResponse().getHeaders().setContentType(MediaType.APPLICATION_JSON);
            String body = "{\"error\":\"Invalid request\",\"message\":\"" + escapeJson(message != null ? message : "Failed to parse request") + "\"}";
            var buffer = exchange.getResponse().bufferFactory().wrap(body.getBytes(StandardCharsets.UTF_8));
            return exchange.getResponse().writeWith(Mono.just(buffer));
        }
        
        if (ex instanceof WebExchangeBindException) {
            WebExchangeBindException bindEx = (WebExchangeBindException) ex;
            log.warn("Validation error: {}", bindEx.getMessage());
            exchange.getResponse().setStatusCode(HttpStatus.BAD_REQUEST);
            exchange.getResponse().getHeaders().setContentType(MediaType.APPLICATION_JSON);
            String errors = bindEx.getBindingResult().getFieldErrors().stream()
                    .map(error -> error.getField() + ": " + error.getDefaultMessage())
                    .reduce((a, b) -> a + ", " + b)
                    .orElse("Validation failed");
            String body = "{\"error\":\"Invalid request body\",\"details\":[\"" + escapeJson(errors) + "\"]}";
            var buffer = exchange.getResponse().bufferFactory().wrap(body.getBytes(StandardCharsets.UTF_8));
            return exchange.getResponse().writeWith(Mono.just(buffer));
        }
        
        // Last resort: check if this looks like a request parsing/validation error
        // This catches cases where exceptions are wrapped or have different class names
        if (message != null || className != null) {
            String lowerMessage = message != null ? message.toLowerCase() : "";
            String lowerClassName = className != null ? className.toLowerCase() : "";
            
            if (lowerMessage.contains("content-type") || 
                lowerMessage.contains("media type") ||
                lowerMessage.contains("unsupported") ||
                lowerMessage.contains("cannot decode") ||
                lowerMessage.contains("failed to parse") ||
                lowerClassName.contains("codec") ||
                lowerClassName.contains("decode") ||
                lowerClassName.contains("parse") ||
                lowerClassName.contains("json") ||
                lowerClassName.contains("jackson")) {
                log.warn("Request parsing/validation error (caught by fallback): {}", ex.getMessage());
                exchange.getResponse().setStatusCode(HttpStatus.BAD_REQUEST);
                exchange.getResponse().getHeaders().setContentType(MediaType.APPLICATION_JSON);
                String body = "{\"error\":\"Invalid request\",\"message\":\"" + 
                    escapeJson(message != null ? message : "Request parsing failed") + "\"}";
                var buffer = exchange.getResponse().bufferFactory().wrap(body.getBytes(StandardCharsets.UTF_8));
                return exchange.getResponse().writeWith(Mono.just(buffer));
            }
        }
        
        // Let other handlers process it
        return Mono.error(ex);
    }
    
    private String escapeJson(String str) {
        if (str == null) {
            return "";
        }
        return str.replace("\\", "\\\\")
                  .replace("\"", "\\\"")
                  .replace("\n", "\\n")
                  .replace("\r", "\\r")
                  .replace("\t", "\\t");
    }
}
