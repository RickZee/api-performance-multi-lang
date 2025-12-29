package com.example.metadata.service;

import com.example.metadata.config.AppConfig;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;
import reactor.core.publisher.Mono;
import reactor.util.retry.Retry;

import java.time.Duration;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;

/**
 * Service for triggering Jenkins CI/CD builds when filters are changed via API.
 * This enables change management and automated testing for API-driven filter changes.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class JenkinsTriggerService {
    private final AppConfig config;
    private final WebClient.Builder webClientBuilder;

    /**
     * Check if Jenkins triggering is enabled and configured.
     */
    public boolean isEnabled() {
        AppConfig.JenkinsConfig jenkinsConfig = config.getJenkins();
        if (jenkinsConfig == null || !jenkinsConfig.isEnabled()) {
            return false;
        }
        String baseUrl = jenkinsConfig.getBaseUrl();
        String jobName = jenkinsConfig.getJobName();
        return baseUrl != null && !baseUrl.trim().isEmpty() 
            && jobName != null && !jobName.trim().isEmpty();
    }

    /**
     * Trigger a Jenkins build for a filter change event.
     * 
     * @param eventType The type of event (create, update, delete, deploy, approve)
     * @param filterId The ID of the filter that changed
     * @param version The version of the filter
     * @param additionalParams Additional parameters to pass to the Jenkins build
     */
    public void triggerBuild(String eventType, String filterId, String version, Map<String, String> additionalParams) {
        if (!isEnabled()) {
            log.debug("Jenkins triggering is disabled, skipping build trigger for event: {}", eventType);
            return;
        }

        AppConfig.JenkinsConfig jenkinsConfig = config.getJenkins();
        
        // Check if this event type should trigger a build
        if (!shouldTriggerForEvent(eventType, jenkinsConfig)) {
            log.debug("Jenkins triggering is disabled for event type: {}", eventType);
            return;
        }

        try {
            String buildUrl = buildJenkinsUrl(jenkinsConfig);
            log.info("Triggering Jenkins build for event: {} (filterId: {}, version: {})", 
                eventType, filterId, version);

            WebClient webClient = createWebClient(jenkinsConfig);
            
            // Build parameters
            Map<String, String> params = new HashMap<>();
            params.put("FILTER_EVENT_TYPE", eventType);
            params.put("FILTER_ID", filterId != null ? filterId : "");
            params.put("FILTER_VERSION", version != null ? version : "v1");
            if (additionalParams != null) {
                params.putAll(additionalParams);
            }

            // Trigger build with parameters
            triggerBuildWithParameters(webClient, buildUrl, params)
                .doOnSuccess(response -> {
                    log.info("Successfully triggered Jenkins build for event: {} (filterId: {})", 
                        eventType, filterId);
                })
                .doOnError(error -> {
                    log.warn("Failed to trigger Jenkins build for event: {} (filterId: {}): {}", 
                        eventType, filterId, error.getMessage());
                })
                .block(Duration.ofSeconds(jenkinsConfig.getTimeoutSeconds()));
                
        } catch (Exception e) {
            // Log error but don't fail the filter operation
            log.warn("Error triggering Jenkins build for event: {} (filterId: {}): {}", 
                eventType, filterId, e.getMessage(), e);
        }
    }

    /**
     * Trigger a simple build (without parameters).
     */
    public void triggerSimpleBuild(String eventType, String filterId, String version) {
        triggerBuild(eventType, filterId, version, null);
    }

    /**
     * Check if a build should be triggered for the given event type.
     */
    private boolean shouldTriggerForEvent(String eventType, AppConfig.JenkinsConfig jenkinsConfig) {
        if (eventType == null) {
            return false;
        }
        
        return switch (eventType.toLowerCase()) {
            case "create" -> jenkinsConfig.isTriggerOnCreate();
            case "update" -> jenkinsConfig.isTriggerOnUpdate();
            case "delete" -> jenkinsConfig.isTriggerOnDelete();
            case "deploy" -> jenkinsConfig.isTriggerOnDeploy();
            case "approve" -> jenkinsConfig.isTriggerOnApprove();
            default -> false;
        };
    }

    /**
     * Build the Jenkins build URL.
     */
    private String buildJenkinsUrl(AppConfig.JenkinsConfig jenkinsConfig) {
        String baseUrl = jenkinsConfig.getBaseUrl().replaceAll("/$", "");
        String jobName = jenkinsConfig.getJobName();
        
        // Use build token if available, otherwise use standard build endpoint
        String buildToken = jenkinsConfig.getBuildToken();
        if (buildToken != null && !buildToken.trim().isEmpty()) {
            return String.format("%s/job/%s/build?token=%s", baseUrl, jobName, buildToken);
        }
        
        return String.format("%s/job/%s/build", baseUrl, jobName);
    }

    /**
     * Create a WebClient configured with authentication if needed.
     */
    private WebClient createWebClient(AppConfig.JenkinsConfig jenkinsConfig) {
        WebClient.Builder builder = webClientBuilder
            .baseUrl(jenkinsConfig.getBaseUrl())
            .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_FORM_URLENCODED_VALUE);

        // Add authentication if credentials are provided
        String username = jenkinsConfig.getUsername();
        String apiToken = jenkinsConfig.getApiToken();
        
        if (username != null && !username.trim().isEmpty() 
            && apiToken != null && !apiToken.trim().isEmpty()) {
            String auth = username + ":" + apiToken;
            String encodedAuth = Base64.getEncoder().encodeToString(auth.getBytes());
            builder.defaultHeader(HttpHeaders.AUTHORIZATION, "Basic " + encodedAuth);
        }

        return builder.build();
    }

    /**
     * Trigger a Jenkins build with parameters using form data.
     */
    private Mono<String> triggerBuildWithParameters(WebClient webClient, String buildUrl, Map<String, String> params) {
        // Build form data
        StringBuilder formData = new StringBuilder();
        formData.append("json=");
        
        // Build JSON payload for parameterized build
        StringBuilder jsonPayload = new StringBuilder();
        jsonPayload.append("{");
        jsonPayload.append("\"parameter\":[");
        
        boolean first = true;
        for (Map.Entry<String, String> entry : params.entrySet()) {
            if (!first) {
                jsonPayload.append(",");
            }
            jsonPayload.append("{");
            jsonPayload.append("\"name\":\"").append(escapeJson(entry.getKey())).append("\",");
            jsonPayload.append("\"value\":\"").append(escapeJson(entry.getValue())).append("\"");
            jsonPayload.append("}");
            first = false;
        }
        
        jsonPayload.append("]");
        jsonPayload.append("}");
        
        // URL encode the JSON
        String jsonEncoded = java.net.URLEncoder.encode(jsonPayload.toString(), java.nio.charset.StandardCharsets.UTF_8);
        formData.append(jsonEncoded);

        // If build token is used, append it to URL
        AppConfig.JenkinsConfig jenkinsConfig = config.getJenkins();
        String buildToken = jenkinsConfig.getBuildToken();
        if (buildToken != null && !buildToken.trim().isEmpty() && !buildUrl.contains("token=")) {
            buildUrl += (buildUrl.contains("?") ? "&" : "?") + "token=" + buildToken;
        }

        return webClient.post()
            .uri(buildUrl)
            .bodyValue(formData.toString())
            .retrieve()
            .bodyToMono(String.class)
            .retryWhen(Retry.backoff(2, Duration.ofSeconds(1))
                .filter(throwable -> throwable instanceof WebClientResponseException 
                    && ((WebClientResponseException) throwable).getStatusCode().is5xxServerError()))
            .timeout(Duration.ofSeconds(jenkinsConfig.getTimeoutSeconds()));
    }

    /**
     * Escape special characters in JSON strings.
     */
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

