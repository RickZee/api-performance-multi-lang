package io.debezium.connector.dsql.auth;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.rds.RdsClient;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.concurrent.locks.ReentrantLock;

/**
 * Generates and caches IAM authentication tokens for Aurora DSQL.
 * 
 * Tokens are valid for 15 minutes. This class implements caching
 * to avoid regenerating tokens on every call, refreshing tokens
 * when they're within 1 minute of expiration.
 * 
 * Thread-safe implementation with synchronized token refresh.
 */
public class IamTokenGenerator {
    private static final Logger LOGGER = LoggerFactory.getLogger(IamTokenGenerator.class);
    
    private static final int TOKEN_VALIDITY_MINUTES = 15;
    private static final int TOKEN_REFRESH_BUFFER_MINUTES = 1; // Refresh 1 minute before expiry
    
    private final String endpoint;
    private final int port;
    private final String iamUsername;
    private final Region region;
    private final RdsClient rdsClient;
    
    private final ReentrantLock lock = new ReentrantLock();
    private volatile CachedToken cachedToken;
    
    /**
     * Internal class to hold cached token with expiration time.
     */
    private static class CachedToken {
        final String token;
        final Instant expiresAt;
        final String cacheKey;
        
        CachedToken(String token, Instant expiresAt, String cacheKey) {
            this.token = token;
            this.expiresAt = expiresAt;
            this.cacheKey = cacheKey;
        }
        
        boolean isValid(String expectedKey) {
            return cacheKey.equals(expectedKey) && 
                   expiresAt.isAfter(Instant.now().plus(TOKEN_REFRESH_BUFFER_MINUTES, ChronoUnit.MINUTES));
        }
    }
    
    public IamTokenGenerator(String endpoint, int port, String iamUsername, String region) {
        this.endpoint = endpoint;
        this.port = port;
        this.iamUsername = iamUsername;
        this.region = Region.of(region);
        this.rdsClient = RdsClient.builder()
                .region(this.region)
                .credentialsProvider(DefaultCredentialsProvider.create())
                .build();
    }
    
    /**
     * Get a valid IAM authentication token, generating a new one if needed.
     * 
     * @return IAM authentication token (valid for 15 minutes)
     */
    public String getToken() {
        String cacheKey = buildCacheKey();
        
        // Check if cached token is still valid
        CachedToken current = cachedToken;
        if (current != null && current.isValid(cacheKey)) {
            LOGGER.debug("Using cached IAM auth token");
            return current.token;
        }
        
        // Need to generate new token - acquire lock
        lock.lock();
        try {
            // Double-check after acquiring lock
            current = cachedToken;
            if (current != null && current.isValid(cacheKey)) {
                LOGGER.debug("Using cached IAM auth token (after lock)");
                return current.token;
            }
            
            // Generate new token
            LOGGER.info("Generating new IAM auth token for Aurora DSQL endpoint: {}", endpoint);
            String newToken = generateNewToken();
            
            // Cache the token (valid for 15 minutes, but we'll expire it at 14 minutes)
            Instant expiresAt = Instant.now().plus(TOKEN_VALIDITY_MINUTES - TOKEN_REFRESH_BUFFER_MINUTES, ChronoUnit.MINUTES);
            cachedToken = new CachedToken(newToken, expiresAt, cacheKey);
            
            LOGGER.info("IAM auth token generated and cached successfully");
            return newToken;
        } catch (Exception e) {
            LOGGER.error("Failed to generate IAM auth token: {}", e.getMessage(), e);
            throw new RuntimeException("Failed to generate IAM auth token", e);
        } finally {
            lock.unlock();
        }
    }
    
    /**
     * Generate a new IAM authentication token for DSQL using presigned URL.
     * 
     * DSQL requires a presigned URL with SigV4QueryAuth (service: 'dsql'),
     * not the standard RDS token generation. This is different from Aurora RDS.
     * 
     * Token format: {endpoint}:{port}/?Action=DbConnect&{signature}
     * 
     * NOTE: AWS SDK v2 for Java doesn't have a direct equivalent to Python's SigV4QueryAuth.
     * This implementation uses a Python script as a workaround since we have a working
     * Python implementation. A proper Java implementation would require manual SigV4
     * query string signing.
     * 
     * TODO: Implement proper Java SigV4 query string signing without Python dependency.
     * Reference: producer-api-python-rest-lambda-dsql/repository/iam_auth.py
     */
    private String generateNewToken() {
        try {
            // Use Python script to generate DSQL presigned URL token
            // The Python implementation uses SigV4QueryAuth which works correctly for DSQL
            // We'll call a Python helper script that implements the same logic
            
            // Try to find the Python script in the project
            String pythonScript = System.getenv("DSQL_TOKEN_GENERATOR_SCRIPT");
            if (pythonScript == null || pythonScript.isEmpty()) {
                // Default to a script in the scripts directory
                pythonScript = "../scripts/dsql_connection.py";
            }
            
            ProcessBuilder processBuilder = new ProcessBuilder(
                    "python3", pythonScript,
                    "--endpoint", endpoint,
                    "--port", String.valueOf(port),
                    "--username", iamUsername,
                    "--region", region.id(),
                    "--generate-token-only"
            );
            
            processBuilder.redirectErrorStream(true);
            Process process = processBuilder.start();
            
            // Read the token from stdout
            StringBuilder tokenBuilder = new StringBuilder();
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(process.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    tokenBuilder.append(line);
                }
            }
            
            int exitCode = process.waitFor();
            if (exitCode != 0) {
                throw new RuntimeException("Python token generator script failed with exit code: " + exitCode);
            }
            
            String token = tokenBuilder.toString().trim();
            
            if (token.isEmpty()) {
                throw new RuntimeException("Python script returned empty token");
            }
            
            LOGGER.debug("Generated DSQL presigned URL token via Python script (length: {})", token.length());
            return token;
            
        } catch (Exception e) {
            LOGGER.error("Failed to generate DSQL presigned URL token via Python script: {}", e.getMessage(), e);
            LOGGER.error("Note: This requires Python 3 and boto3 to be installed");
            LOGGER.error("Set DSQL_TOKEN_GENERATOR_SCRIPT environment variable to point to the Python script");
            throw new RuntimeException("Failed to generate DSQL IAM authentication token. " +
                    "Ensure Python 3 and boto3 are installed, or implement proper Java signing.", e);
        }
    }
    
    /**
     * Build cache key for token validation.
     */
    private String buildCacheKey() {
        return String.format("%s:%d:%s", endpoint, port, iamUsername);
    }
    
    /**
     * Clear the token cache (useful for testing or forced refresh).
     */
    public void clearCache() {
        lock.lock();
        try {
            cachedToken = null;
            LOGGER.debug("IAM auth token cache cleared");
        } finally {
            lock.unlock();
        }
    }
    
    /**
     * Close the RDS client and clear cache.
     */
    public void close() {
        lock.lock();
        try {
            if (rdsClient != null) {
                rdsClient.close();
            }
            cachedToken = null;
        } finally {
            lock.unlock();
        }
    }
}
