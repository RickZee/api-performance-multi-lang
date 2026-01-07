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
    private final AppConfig.FlinkConfig.LocalConfig localFlinkConfig;
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
        
        if (appConfig.getFlink() == null) {
            appConfig.setFlink(new AppConfig.FlinkConfig());
        }
        if (appConfig.getFlink().getLocal() == null) {
            appConfig.getFlink().setLocal(new AppConfig.FlinkConfig.LocalConfig());
        }
        this.localFlinkConfig = appConfig.getFlink().getLocal();
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

    // ============================================================================
    // Local Flink Deployment Methods
    // ============================================================================

    public List<String> deployToLocalFlink(List<String> statements, List<String> statementNames) throws IOException {
        if (!localFlinkConfig.isEnabled()) {
            throw new IOException("Local Flink deployment is not enabled");
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

            // Convert SQL to use Kafka connector format (not Confluent connector)
            String localSql = convertToLocalFlinkSql(sql);

            String statementId = deployToLocalFlinkStatement(localSql, statementName);
            statementIds.add(statementId);
            log.info("Flink statement deployed to local cluster: statementName={}, statementId={}", statementName, statementId);
        }

        return statementIds;
    }

    private String deployToLocalFlinkStatement(String sql, String statementName) throws IOException {
        String url = localFlinkConfig.getRestApiUrl();
        if (!url.endsWith("/")) {
            url += "/";
        }
        url += "v1/statements";

        FlinkStatement request = new FlinkStatement();
        request.setName(statementName);
        request.setStatement(sql);

        String jsonBody = objectMapper.writeValueAsString(request);
        StringEntity entity = new StringEntity(jsonBody, StandardCharsets.UTF_8);

        HttpPost httpPost = new HttpPost(url);
        httpPost.setEntity(entity);
        httpPost.setHeader("Content-Type", "application/json");

        try (CloseableHttpResponse response = httpClient.execute(httpPost)) {
            int statusCode = response.getCode();
            String responseBody = new String(response.getEntity().getContent().readAllBytes(), StandardCharsets.UTF_8);

            if (statusCode >= 200 && statusCode < 300) {
                FlinkStatementResponse statementResponse = objectMapper.readValue(responseBody, FlinkStatementResponse.class);
                return statementResponse.getId();
            } else {
                throw new IOException("Failed to deploy statement to local Flink: HTTP " + statusCode + " - " + responseBody);
            }
        }
    }

    public boolean validateLocalFlinkConnection() {
        try {
            if (!localFlinkConfig.isEnabled()) {
                return false;
            }
            String url = localFlinkConfig.getRestApiUrl();
            if (url == null || url.isEmpty()) {
                return false;
            }
            // Test connection by checking Flink overview endpoint
            String testUrl = url.endsWith("/") ? url + "overview" : url + "/overview";
            HttpGet httpGet = new HttpGet(testUrl);
            try (CloseableHttpResponse response = httpClient.execute(httpGet)) {
                return response.getCode() >= 200 && response.getCode() < 300;
            }
        } catch (Exception e) {
            log.warn("Local Flink connection validation failed", e);
            return false;
        }
    }

    /**
     * Convert Confluent Cloud SQL format to local Flink SQL format.
     * Replaces 'confluent' connector with 'kafka' connector and updates format.
     */
    private String convertToLocalFlinkSql(String sql) {
        // Replace Confluent connector with Kafka connector
        String converted = sql.replaceAll("'connector'\\s*=\\s*'confluent'", "'connector' = 'kafka'");
        
        // Replace json-registry format with json format
        converted = converted.replaceAll("'value\\.format'\\s*=\\s*'json-registry'", "'format' = 'json'");
        
        // Remove Confluent-specific SASL configurations
        converted = converted.replaceAll("'properties\\.sasl\\.(mechanism|jaas\\.config|client\\.callback\\.handler\\.class)'\\s*=\\s*'[^']+',?\\s*", "");
        
        // Update or add bootstrap servers to use local Redpanda
        if (converted.contains("'properties.bootstrap.servers'")) {
            converted = converted.replaceAll(
                "'properties\\.bootstrap\\.servers'\\s*=\\s*'[^']+'",
                "'properties.bootstrap.servers' = 'redpanda:9092'"
            );
        } else {
            // Add bootstrap servers before closing parenthesis
            converted = converted.replaceAll(
                "(\\);)",
                "    'properties.bootstrap.servers' = 'redpanda:9092',\n$1"
            );
        }
        
        // Update or add security protocol to PLAINTEXT for local
        if (converted.contains("'properties.security.protocol'")) {
            converted = converted.replaceAll(
                "'properties\\.security\\.protocol'\\s*=\\s*'[^']+'",
                "'properties.security.protocol' = 'PLAINTEXT'"
            );
        } else {
            // Add security protocol before closing parenthesis
            converted = converted.replaceAll(
                "(\\);)",
                "    'properties.security.protocol' = 'PLAINTEXT',\n$1"
            );
        }
        
        // Add json.ignore-parse-errors if not present
        if (!converted.contains("json.ignore-parse-errors")) {
            // Add before the closing parenthesis of WITH clause
            converted = converted.replaceAll(
                "(\\);)",
                "    'json.ignore-parse-errors' = 'true'\n$1"
            );
        }
        
        return converted;
    }
}
