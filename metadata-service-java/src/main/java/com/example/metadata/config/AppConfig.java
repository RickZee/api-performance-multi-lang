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
    private FlinkConfig flink = new FlinkConfig();
    private SpringBootConfig springBoot = new SpringBootConfig();
    private JenkinsConfig jenkins = new JenkinsConfig();

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

    @Data
    public static class SpringBootConfig {
        private String filtersYamlPath;
        private boolean backupEnabled = true;
        private String backupDir = "/tmp/filters-yaml-backups";
    }

    @Data
    public static class FlinkConfig {
        private LocalConfig local = new LocalConfig();

        @Data
        public static class LocalConfig {
            private boolean enabled = false;
            private String restApiUrl = "http://localhost:8082";
        }
    }

    @Data
    public static class JenkinsConfig {
        private boolean enabled = false;
        private String baseUrl = "http://localhost:8080";
        private String jobName = "filter-integration-tests";
        private String username;
        private String apiToken;
        private String buildToken;
        private boolean triggerOnCreate = true;
        private boolean triggerOnUpdate = true;
        private boolean triggerOnDelete = true;
        private boolean triggerOnDeploy = true;
        private boolean triggerOnApprove = true;
        private int timeoutSeconds = 30;
    }
}
