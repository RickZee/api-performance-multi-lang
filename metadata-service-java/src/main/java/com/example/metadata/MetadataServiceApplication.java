package com.example.metadata;

import com.example.metadata.config.AppConfig;
import com.example.metadata.service.GitSyncService;
import jakarta.annotation.PreDestroy;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.condition.ConditionalOnBean;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;

@SpringBootApplication
@EnableConfigurationProperties(AppConfig.class)
@Slf4j
public class MetadataServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(MetadataServiceApplication.class, args);
    }

    @Bean
    @ConditionalOnBean(GitSyncService.class)
    public CommandLineRunner startGitSync(@Autowired(required = false) GitSyncService gitSyncService, AppConfig config) {
        return args -> {
            // Skip GitSync startup in test mode or if service is not available
            if (System.getProperty("test.mode") != null || System.getenv("TEST_MODE") != null) {
                log.info("Skipping git sync startup in test mode");
                return;
            }
            
            // Handle null config or service gracefully (e.g., in test contexts)
            if (gitSyncService == null || config == null || config.getGit() == null) {
                log.warn("Git sync service or config not available, skipping git sync startup");
                return;
            }
            
            log.info("Starting metadata service: repository={}, branch={}, port={}",
                config.getGit().getRepository(),
                config.getGit().getBranch(),
                8080);
            
            try {
                gitSyncService.start();
            } catch (Exception e) {
                log.error("Git sync startup failed", e);
                throw e;
            }
        };
    }

    @Bean
    @ConditionalOnBean(GitSyncService.class)
    public GitSyncShutdownHook gitSyncShutdownHook(@Autowired(required = false) GitSyncService gitSyncService) {
        if (gitSyncService == null) {
            return new GitSyncShutdownHook(null);
        }
        return new GitSyncShutdownHook(gitSyncService);
    }

    private static class GitSyncShutdownHook {
        private final GitSyncService gitSyncService;

        public GitSyncShutdownHook(GitSyncService gitSyncService) {
            this.gitSyncService = gitSyncService;
            if (gitSyncService != null) {
                Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                    log.info("Shutting down metadata service...");
                    gitSyncService.stop();
                }));
            }
        }
    }
}
