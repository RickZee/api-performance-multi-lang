package com.example.streamprocessor.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

import java.util.List;

/**
 * Configuration class that loads filters from filters.yml.
 */
@Configuration
@ConfigurationProperties(prefix = "")
@Data
public class FiltersConfig {
    private List<FilterConfig> filters;
}

