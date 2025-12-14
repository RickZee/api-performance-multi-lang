package com.example.metadata.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

import java.util.List;

@ConfigurationProperties(prefix = "")
@Data
public class AppConfig {
    private GitConfig git = new GitConfig();
    private ValidationConfig validation = new ValidationConfig();
    private ConfluentConfig confluent = new ConfluentConfig();

    @Data
    public static class GitConfig {
        private String repository;
        private String branch = "main";
        private String pullInterval = "PT5M"; // ISO-8601 duration
        private String localCacheDir = "/tmp/schema-cache";
    }

    @Data
    public static class ValidationConfig {
        private String defaultVersion = "latest";
        private List<String> acceptedVersions = List.of("v1", "v2");
        private boolean strictMode = true;
    }

    @Data
    public static class ConfluentConfig {
        private CloudConfig cloud = new CloudConfig();

        @Data
        public static class CloudConfig {
            private String apiKey;
            private String apiSecret;
            private String flinkComputePoolId;
            private String flinkApiEndpoint;
        }
    }
}
