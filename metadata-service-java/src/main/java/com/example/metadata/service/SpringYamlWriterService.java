package com.example.metadata.service;

import com.example.metadata.config.AppConfig;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.time.Instant;
import java.time.format.DateTimeFormatter;
import java.util.List;

/**
 * Service for writing Spring Boot YAML configuration to file.
 */
@Service
@Slf4j
public class SpringYamlWriterService {
    private AppConfig.SpringBootConfig config;
    private final AppConfig appConfig;

    public SpringYamlWriterService(AppConfig appConfig) {
        this.appConfig = appConfig;
        if (appConfig.getSpringBoot() == null) {
            appConfig.setSpringBoot(new AppConfig.SpringBootConfig());
        }
        this.config = appConfig.getSpringBoot();
    }

    /**
     * Refresh config from AppConfig (useful for tests that update AppConfig).
     * In production, config is read once at construction time.
     */
    public void refreshConfig() {
        if (appConfig.getSpringBoot() == null) {
            appConfig.setSpringBoot(new AppConfig.SpringBootConfig());
        }
        this.config = appConfig.getSpringBoot();
    }

    /**
     * Write YAML content to the configured filters.yml file.
     * Creates backup if enabled, and performs atomic write operation.
     */
    public void writeFiltersYaml(String yaml) throws IOException {
        if (config.getFiltersYamlPath() == null || config.getFiltersYamlPath().isEmpty()) {
            log.warn("Spring Boot filters YAML path not configured, skipping write");
            return;
        }

        Path yamlPath = resolvePath(config.getFiltersYamlPath());
        
        // Create backup if enabled and file exists
        if (config.isBackupEnabled() && Files.exists(yamlPath)) {
            try {
                backupCurrentYaml(yamlPath);
            } catch (IOException e) {
                log.warn("Failed to create backup of filters.yml, continuing with write: {}", e.getMessage());
            }
        }

        // Ensure parent directory exists
        Path parentDir = yamlPath.getParent();
        if (parentDir != null && !Files.exists(parentDir)) {
            Files.createDirectories(parentDir);
            log.info("Created directory: {}", parentDir);
        }

        // Atomic write: write to temp file, then rename
        Path tempFile = yamlPath.resolveSibling(yamlPath.getFileName().toString() + ".tmp");
        try {
            Files.writeString(tempFile, yaml);
            Files.move(tempFile, yamlPath, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
            log.info("Successfully wrote filters.yml to: {}", yamlPath);
        } catch (IOException e) {
            // Clean up temp file if it exists
            try {
                if (Files.exists(tempFile)) {
                    Files.delete(tempFile);
                }
            } catch (IOException cleanupError) {
                log.warn("Failed to clean up temp file: {}", cleanupError.getMessage());
            }
            throw new IOException("Failed to write filters.yml: " + e.getMessage(), e);
        }
    }

    /**
     * Create a backup of the current filters.yml file.
     */
    public void backupCurrentYaml(Path yamlPath) throws IOException {
        if (!Files.exists(yamlPath)) {
            log.debug("No existing filters.yml to backup");
            return;
        }

        Path backupDir = Paths.get(config.getBackupDir());
        if (!Files.exists(backupDir)) {
            Files.createDirectories(backupDir);
            log.info("Created backup directory: {}", backupDir);
        }

        // Create backup filename with timestamp
        String timestamp = DateTimeFormatter.ISO_INSTANT.format(Instant.now())
            .replace(":", "-")
            .replace(".", "-");
        String backupFileName = "filters-" + timestamp + ".yml";
        Path backupPath = backupDir.resolve(backupFileName);

        Files.copy(yamlPath, backupPath, StandardCopyOption.REPLACE_EXISTING);
        log.info("Created backup of filters.yml: {}", backupPath);

        // Clean up old backups (keep last 10)
        cleanupOldBackups(backupDir);
    }

    /**
     * Clean up old backup files, keeping only the most recent ones.
     */
    private void cleanupOldBackups(Path backupDir) {
        try {
            List<Path> backups = Files.list(backupDir)
                .filter(path -> path.getFileName().toString().startsWith("filters-") && 
                               path.getFileName().toString().endsWith(".yml"))
                .sorted((a, b) -> {
                    try {
                        return Files.getLastModifiedTime(b).compareTo(Files.getLastModifiedTime(a));
                    } catch (IOException e) {
                        return 0;
                    }
                })
                .collect(java.util.stream.Collectors.toList());

            // Keep last 10 backups
            int maxBackups = 10;
            if (backups.size() > maxBackups) {
                for (int i = maxBackups; i < backups.size(); i++) {
                    Files.delete(backups.get(i));
                    log.debug("Deleted old backup: {}", backups.get(i));
                }
            }
        } catch (IOException e) {
            log.warn("Failed to clean up old backups: {}", e.getMessage());
        }
    }

    /**
     * Resolve the path to filters.yml file.
     * Supports absolute paths, relative paths, and environment variable expansion.
     */
    public Path resolvePath(String pathString) {
        if (pathString == null || pathString.isEmpty()) {
            throw new IllegalArgumentException("Filters YAML path cannot be null or empty");
        }

        // Expand environment variables
        String expandedPath = expandEnvironmentVariables(pathString);

        Path path = Paths.get(expandedPath);
        
        // If relative path, resolve relative to current working directory
        if (!path.isAbsolute()) {
            path = Paths.get(System.getProperty("user.dir")).resolve(path).normalize();
        }

        return path;
    }

    /**
     * Expand environment variables in path string.
     */
    private String expandEnvironmentVariables(String path) {
        String result = path;
        // Simple expansion: ${VAR} or $VAR
        int start = result.indexOf("${");
        while (start != -1) {
            int end = result.indexOf("}", start);
            if (end != -1) {
                String varName = result.substring(start + 2, end);
                String varValue = System.getenv(varName);
                if (varValue != null) {
                    result = result.substring(0, start) + varValue + result.substring(end + 1);
                    // After substitution, search from the beginning again to catch nested/overlapping patterns
                    start = result.indexOf("${");
                } else {
                    // Variable not found, skip past this ${} pattern
                    start = result.indexOf("${", end + 1);
                }
            } else {
                break;
            }
        }
        return result;
    }

    /**
     * Get the configured filters YAML path.
     */
    public Path getFiltersYamlPath() {
        if (config.getFiltersYamlPath() == null || config.getFiltersYamlPath().isEmpty()) {
            return null;
        }
        return resolvePath(config.getFiltersYamlPath());
    }

    /**
     * Check if YAML writing is enabled (path is configured).
     */
    public boolean isEnabled() {
        return config.getFiltersYamlPath() != null && !config.getFiltersYamlPath().isEmpty();
    }
}

