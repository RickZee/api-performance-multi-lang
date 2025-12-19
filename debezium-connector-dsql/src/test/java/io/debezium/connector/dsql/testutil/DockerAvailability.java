package io.debezium.connector.dsql.testutil;

import org.testcontainers.DockerClientFactory;

import java.io.File;

/**
 * Utility class to check Docker availability for Testcontainers.
 * 
 * Provides methods to verify Docker is accessible and provides
 * helpful error messages if Docker is not available.
 */
public class DockerAvailability {
    
    /**
     * Check if Docker is available for Testcontainers.
     * 
     * @return true if Docker is available, false otherwise
     */
    public static boolean isDockerAvailable() {
        try {
            return DockerClientFactory.instance().isDockerAvailable();
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * Check Docker availability and return a detailed status message.
     * 
     * @return Status message describing Docker availability
     */
    public static String getDockerStatus() {
        if (isDockerAvailable()) {
            return "Docker is available and accessible";
        }
        
        StringBuilder status = new StringBuilder("Docker is not available. ");
        status.append("Please check the following:\n");
        
        // Check common Docker socket locations
        boolean foundSocket = false;
        
        // Check default socket
        File defaultSocket = new File("/var/run/docker.sock");
        if (defaultSocket.exists()) {
            status.append("  - Found /var/run/docker.sock (Docker Desktop default socket enabled)\n");
            foundSocket = true;
        }
        
        // Check macOS Docker Desktop socket
        String homeDir = System.getProperty("user.home");
        File macSocket = new File(homeDir + "/.docker/run/docker.sock");
        if (macSocket.exists()) {
            status.append("  - Found ").append(macSocket.getAbsolutePath()).append(" (macOS Docker Desktop)\n");
            foundSocket = true;
        }
        
        // Check DOCKER_HOST environment variable
        String dockerHost = System.getenv("DOCKER_HOST");
        if (dockerHost != null && !dockerHost.isEmpty()) {
            status.append("  - DOCKER_HOST is set to: ").append(dockerHost).append("\n");
            foundSocket = true;
        }
        
        if (!foundSocket) {
            status.append("  - No Docker socket found at common locations\n");
        }
        
        status.append("\nConfiguration options:\n");
        status.append("  1. Enable 'Enable default Docker socket' in Docker Desktop → Settings → Advanced\n");
        status.append("  2. Set DOCKER_HOST environment variable: export DOCKER_HOST=unix://$HOME/.docker/run/docker.sock\n");
        status.append("  3. Create ~/.testcontainers.properties with docker.host=unix://...\n");
        
        return status.toString();
    }
    
    /**
     * Get the Docker host configuration that Testcontainers is using.
     * 
     * @return Docker host string or "not configured"
     */
    public static String getDockerHost() {
        String dockerHost = System.getenv("DOCKER_HOST");
        if (dockerHost != null && !dockerHost.isEmpty()) {
            return dockerHost;
        }
        
        // Check for common socket locations
        File defaultSocket = new File("/var/run/docker.sock");
        if (defaultSocket.exists()) {
            return "unix:///var/run/docker.sock (auto-detected)";
        }
        
        String homeDir = System.getProperty("user.home");
        File macSocket = new File(homeDir + "/.docker/run/docker.sock");
        if (macSocket.exists()) {
            return "unix://" + macSocket.getAbsolutePath() + " (auto-detected)";
        }
        
        return "not configured (using auto-detection)";
    }
    
    /**
     * Verify Docker is available, throwing an exception with helpful message if not.
     * 
     * @throws IllegalStateException if Docker is not available
     */
    public static void requireDocker() {
        if (!isDockerAvailable()) {
            throw new IllegalStateException(getDockerStatus());
        }
    }
}
