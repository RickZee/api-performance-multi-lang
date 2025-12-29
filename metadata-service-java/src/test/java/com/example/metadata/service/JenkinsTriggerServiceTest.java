package com.example.metadata.service;

import com.example.metadata.config.AppConfig;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClient.RequestBodyUriSpec;
import org.springframework.web.reactive.function.client.WebClient.RequestBodySpec;
import org.springframework.web.reactive.function.client.WebClient.RequestHeadersSpec;
import org.springframework.web.reactive.function.client.WebClient.ResponseSpec;
import reactor.core.publisher.Mono;

import java.util.HashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@org.mockito.junit.jupiter.MockitoSettings(strictness = org.mockito.quality.Strictness.LENIENT)
class JenkinsTriggerServiceTest {
    @Mock
    private AppConfig appConfig;
    
    @Mock
    private AppConfig.JenkinsConfig jenkinsConfig;
    
    @Mock
    private WebClient.Builder webClientBuilder;
    
    @Mock
    private WebClient webClient;
    
    @Mock
    private RequestBodyUriSpec requestBodyUriSpec;
    
    @Mock
    private RequestBodySpec requestBodySpec;
    
    @Mock
    private RequestHeadersSpec<?> requestHeadersSpec;
    
    @Mock
    private ResponseSpec responseSpec;
    
    private JenkinsTriggerService jenkinsTriggerService;

    @BeforeEach
    void setUp() {
        when(appConfig.getJenkins()).thenReturn(jenkinsConfig);
        when(webClientBuilder.baseUrl(anyString())).thenReturn(webClientBuilder);
        when(webClientBuilder.defaultHeader(anyString(), anyString())).thenReturn(webClientBuilder);
        when(webClientBuilder.build()).thenReturn(webClient);
        when(webClient.post()).thenReturn(requestBodyUriSpec);
        when(requestBodyUriSpec.uri(anyString())).thenReturn(requestBodySpec);
        doReturn(requestHeadersSpec).when(requestBodySpec).bodyValue(anyString());
        when(requestHeadersSpec.retrieve()).thenReturn(responseSpec);
        
        // Mock the Mono chain with retry and timeout
        Mono<String> successMono = Mono.just("Success");
        when(responseSpec.bodyToMono(String.class)).thenReturn(successMono);
        
        jenkinsTriggerService = new JenkinsTriggerService(appConfig, webClientBuilder);
    }

    @Test
    void testIsEnabled_WhenDisabled() {
        when(jenkinsConfig.isEnabled()).thenReturn(false);
        
        assertThat(jenkinsTriggerService.isEnabled()).isFalse();
    }

    @Test
    void testIsEnabled_WhenEnabledButMissingConfig() {
        when(jenkinsConfig.isEnabled()).thenReturn(true);
        when(jenkinsConfig.getBaseUrl()).thenReturn(null);
        when(jenkinsConfig.getJobName()).thenReturn("test-job");
        
        assertThat(jenkinsTriggerService.isEnabled()).isFalse();
    }

    @Test
    void testIsEnabled_WhenEnabledAndConfigured() {
        when(jenkinsConfig.isEnabled()).thenReturn(true);
        when(jenkinsConfig.getBaseUrl()).thenReturn("http://jenkins:8080");
        when(jenkinsConfig.getJobName()).thenReturn("test-job");
        
        assertThat(jenkinsTriggerService.isEnabled()).isTrue();
    }

    @Test
    void testTriggerBuild_WhenDisabled() {
        when(jenkinsConfig.isEnabled()).thenReturn(false);
        
        jenkinsTriggerService.triggerBuild("create", "filter-1", "v1", null);
        
        verify(webClient, never()).post();
    }

    @Test
    void testTriggerBuild_WhenEventTypeNotEnabled() {
        when(jenkinsConfig.isEnabled()).thenReturn(true);
        when(jenkinsConfig.getBaseUrl()).thenReturn("http://jenkins:8080");
        when(jenkinsConfig.getJobName()).thenReturn("test-job");
        when(jenkinsConfig.isTriggerOnCreate()).thenReturn(false);
        
        jenkinsTriggerService.triggerBuild("create", "filter-1", "v1", null);
        
        verify(webClient, never()).post();
    }

    @Test
    void testTriggerBuild_WhenEnabled() {
        when(jenkinsConfig.isEnabled()).thenReturn(true);
        when(jenkinsConfig.getBaseUrl()).thenReturn("http://jenkins:8080");
        when(jenkinsConfig.getJobName()).thenReturn("test-job");
        when(jenkinsConfig.isTriggerOnCreate()).thenReturn(true);
        when(jenkinsConfig.getTimeoutSeconds()).thenReturn(30);
        when(jenkinsConfig.getBuildToken()).thenReturn(null);
        when(jenkinsConfig.getUsername()).thenReturn(null);
        when(jenkinsConfig.getApiToken()).thenReturn(null);
        
        jenkinsTriggerService.triggerBuild("create", "filter-1", "v1", null);
        
        verify(webClient).post();
    }

    @Test
    void testTriggerBuild_WithAuthentication() {
        when(jenkinsConfig.isEnabled()).thenReturn(true);
        when(jenkinsConfig.getBaseUrl()).thenReturn("http://jenkins:8080");
        when(jenkinsConfig.getJobName()).thenReturn("test-job");
        when(jenkinsConfig.isTriggerOnCreate()).thenReturn(true);
        when(jenkinsConfig.getTimeoutSeconds()).thenReturn(30);
        when(jenkinsConfig.getBuildToken()).thenReturn(null);
        when(jenkinsConfig.getUsername()).thenReturn("admin");
        when(jenkinsConfig.getApiToken()).thenReturn("token123");
        
        jenkinsTriggerService.triggerBuild("create", "filter-1", "v1", null);
        
        verify(webClientBuilder).defaultHeader(eq("Authorization"), anyString());
        verify(webClient).post();
    }

    @Test
    void testTriggerBuild_WithBuildToken() {
        when(jenkinsConfig.isEnabled()).thenReturn(true);
        when(jenkinsConfig.getBaseUrl()).thenReturn("http://jenkins:8080");
        when(jenkinsConfig.getJobName()).thenReturn("test-job");
        when(jenkinsConfig.isTriggerOnCreate()).thenReturn(true);
        when(jenkinsConfig.getTimeoutSeconds()).thenReturn(30);
        when(jenkinsConfig.getBuildToken()).thenReturn("build-token-123");
        when(jenkinsConfig.getUsername()).thenReturn(null);
        when(jenkinsConfig.getApiToken()).thenReturn(null);
        
        jenkinsTriggerService.triggerBuild("create", "filter-1", "v1", null);
        
        verify(webClient).post();
    }

    @Test
    void testTriggerBuild_WithAdditionalParams() {
        when(jenkinsConfig.isEnabled()).thenReturn(true);
        when(jenkinsConfig.getBaseUrl()).thenReturn("http://jenkins:8080");
        when(jenkinsConfig.getJobName()).thenReturn("test-job");
        when(jenkinsConfig.isTriggerOnCreate()).thenReturn(true);
        when(jenkinsConfig.getTimeoutSeconds()).thenReturn(30);
        when(jenkinsConfig.getBuildToken()).thenReturn(null);
        when(jenkinsConfig.getUsername()).thenReturn(null);
        when(jenkinsConfig.getApiToken()).thenReturn(null);
        
        Map<String, String> params = new HashMap<>();
        params.put("CUSTOM_PARAM", "value");
        
        jenkinsTriggerService.triggerBuild("create", "filter-1", "v1", params);
        
        verify(webClient).post();
    }

    @Test
    void testTriggerSimpleBuild() {
        when(jenkinsConfig.isEnabled()).thenReturn(true);
        when(jenkinsConfig.getBaseUrl()).thenReturn("http://jenkins:8080");
        when(jenkinsConfig.getJobName()).thenReturn("test-job");
        when(jenkinsConfig.isTriggerOnCreate()).thenReturn(true);
        when(jenkinsConfig.getTimeoutSeconds()).thenReturn(30);
        when(jenkinsConfig.getBuildToken()).thenReturn(null);
        when(jenkinsConfig.getUsername()).thenReturn(null);
        when(jenkinsConfig.getApiToken()).thenReturn(null);
        
        jenkinsTriggerService.triggerSimpleBuild("create", "filter-1", "v1");
        
        verify(webClient).post();
    }

    @Test
    void testTriggerBuild_HandlesExceptionGracefully() {
        when(jenkinsConfig.isEnabled()).thenReturn(true);
        when(jenkinsConfig.getBaseUrl()).thenReturn("http://jenkins:8080");
        when(jenkinsConfig.getJobName()).thenReturn("test-job");
        when(jenkinsConfig.isTriggerOnCreate()).thenReturn(true);
        when(jenkinsConfig.getTimeoutSeconds()).thenReturn(30);
        when(jenkinsConfig.getBuildToken()).thenReturn(null);
        when(jenkinsConfig.getUsername()).thenReturn(null);
        when(jenkinsConfig.getApiToken()).thenReturn(null);
        
        when(responseSpec.bodyToMono(String.class)).thenReturn(Mono.error(new RuntimeException("Connection failed")));
        
        // Should not throw exception
        jenkinsTriggerService.triggerBuild("create", "filter-1", "v1", null);
        
        verify(webClient).post();
    }
}

