package com.example.metadata.service;

import com.example.metadata.config.AppConfig;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import org.apache.hc.client5.http.classic.methods.HttpDelete;
import org.apache.hc.client5.http.classic.methods.HttpGet;
import org.apache.hc.client5.http.classic.methods.HttpPost;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.client5.http.impl.classic.CloseableHttpResponse;
import org.apache.hc.client5.http.impl.classic.HttpClients;
import org.apache.hc.core5.http.io.entity.StringEntity;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.Base64;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Service
@Slf4j
public class FilterDeployerService {
    private final AppConfig.ConfluentConfig.CloudConfig config;
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final CloseableHttpClient httpClient = HttpClients.createDefault();

    public FilterDeployerService(AppConfig appConfig) {
        if (appConfig.getConfluent() == null) {
            appConfig.setConfluent(new AppConfig.ConfluentConfig());
        }
        if (appConfig.getConfluent().getCloud() == null) {
            appConfig.getConfluent().setCloud(new AppConfig.ConfluentConfig.CloudConfig());
        }
        this.config = appConfig.getConfluent().getCloud();
    }

    @Data
    public static class FlinkStatement {
        private String name;
        private String statement;
    }

    @Data
    public static class FlinkStatementResponse {
        private String id;
        private String name;
        private String status;
        private String error;
    }

    public List<String> deployStatements(List<String> statements, List<String> statementNames) throws IOException {
        if (config.getApiKey() == null || config.getApiKey().isEmpty() ||
            config.getApiSecret() == null || config.getApiSecret().isEmpty()) {
            throw new IOException("Confluent Cloud API credentials not configured");
        }

        if (config.getFlinkComputePoolId() == null || config.getFlinkComputePoolId().isEmpty()) {
            throw new IOException("Confluent Cloud compute pool ID not configured");
        }

        if (statements.size() != statementNames.size()) {
            throw new IllegalArgumentException("statements and statementNames must have the same length");
        }

        List<String> statementIds = new ArrayList<>();

        for (int i = 0; i < statements.size(); i++) {
            String sql = statements.get(i);
            String statementName = statementNames.get(i);
            if (statementName == null || statementName.isEmpty()) {
                statementName = "statement-" + (i + 1);
            }

            String statementId = deployStatement(sql, statementName);
            statementIds.add(statementId);
            log.info("Flink statement deployed: statementName={}, statementId={}", statementName, statementId);
        }

        return statementIds;
    }

    private String deployStatement(String sql, String statementName) throws IOException {
        String url = buildApiUrl("/v1/compute-pools/" + config.getFlinkComputePoolId() + "/statements");

        FlinkStatement request = new FlinkStatement();
        request.setName(statementName);
        request.setStatement(sql);

        String jsonBody = objectMapper.writeValueAsString(request);
        StringEntity entity = new StringEntity(jsonBody, StandardCharsets.UTF_8);

        HttpPost httpPost = new HttpPost(url);
        httpPost.setEntity(entity);
        httpPost.setHeader("Content-Type", "application/json");
        httpPost.setHeader("Authorization", getAuthHeader());

        try (CloseableHttpResponse response = httpClient.execute(httpPost)) {
            int statusCode = response.getCode();
            String responseBody = new String(response.getEntity().getContent().readAllBytes(), StandardCharsets.UTF_8);

            if (statusCode >= 200 && statusCode < 300) {
                FlinkStatementResponse statementResponse = objectMapper.readValue(responseBody, FlinkStatementResponse.class);
                return statementResponse.getId();
            } else {
                throw new IOException("Failed to deploy statement: HTTP " + statusCode + " - " + responseBody);
            }
        }
    }

    public FlinkStatementResponse getStatementStatus(String statementId) throws IOException {
        String url = buildApiUrl("/v1/compute-pools/" + config.getFlinkComputePoolId() + "/statements/" + statementId);

        HttpGet httpGet = new HttpGet(url);
        httpGet.setHeader("Authorization", getAuthHeader());

        try (CloseableHttpResponse response = httpClient.execute(httpGet)) {
            int statusCode = response.getCode();
            String responseBody = new String(response.getEntity().getContent().readAllBytes(), StandardCharsets.UTF_8);

            if (statusCode >= 200 && statusCode < 300) {
                return objectMapper.readValue(responseBody, FlinkStatementResponse.class);
            } else {
                throw new IOException("Failed to get statement status: HTTP " + statusCode + " - " + responseBody);
            }
        }
    }

    public void deleteStatement(String statementId) throws IOException {
        String url = buildApiUrl("/v1/compute-pools/" + config.getFlinkComputePoolId() + "/statements/" + statementId);

        HttpDelete httpDelete = new HttpDelete(url);
        httpDelete.setHeader("Authorization", getAuthHeader());

        try (CloseableHttpResponse response = httpClient.execute(httpDelete)) {
            int statusCode = response.getCode();
            if (statusCode < 200 || statusCode >= 300) {
                String responseBody = new String(response.getEntity().getContent().readAllBytes(), StandardCharsets.UTF_8);
                throw new IOException("Failed to delete statement: HTTP " + statusCode + " - " + responseBody);
            }
        }
    }

    public boolean validateConnection() {
        try {
            if (config.getApiKey() == null || config.getApiKey().isEmpty() ||
                config.getApiSecret() == null || config.getApiSecret().isEmpty()) {
                return false;
            }
            if (config.getFlinkComputePoolId() == null || config.getFlinkComputePoolId().isEmpty()) {
                return false;
            }
            // Could add a test API call here
            return true;
        } catch (Exception e) {
            log.warn("Connection validation failed", e);
            return false;
        }
    }

    public List<String> extractStatementNames(String sql) {
        List<String> names = new ArrayList<>();
        // Extract CREATE TABLE statement names
        Pattern pattern = Pattern.compile("CREATE\\s+TABLE\\s+`?([^`\\s]+)`?", Pattern.CASE_INSENSITIVE);
        Matcher matcher = pattern.matcher(sql);
        while (matcher.find()) {
            names.add(matcher.group(1));
        }
        return names;
    }

    private String buildApiUrl(String path) {
        String endpoint = config.getFlinkApiEndpoint();
        if (endpoint == null || endpoint.isEmpty()) {
            endpoint = "https://flink.us-east-1.aws.confluent.cloud";
        }
        if (!endpoint.endsWith("/")) {
            endpoint += "/";
        }
        if (path.startsWith("/")) {
            path = path.substring(1);
        }
        return endpoint + path;
    }

    private String getAuthHeader() {
        String credentials = config.getApiKey() + ":" + config.getApiSecret();
        String encoded = Base64.getEncoder().encodeToString(credentials.getBytes(StandardCharsets.UTF_8));
        return "Basic " + encoded;
    }
}
