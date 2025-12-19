package io.debezium.connector.dsql.auth;

import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.AwsCredentials;

import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * Test utilities for IamTokenGenerator tests.
 */
class IamTokenGeneratorTestUtils {
    
    // More flexible pattern - query parameters can be in any order
    private static final Pattern TOKEN_PATTERN = Pattern.compile(
        "^[^:]+:\\d+/\\?.*Action=DbConnect.*X-Amz-Algorithm=AWS4-HMAC-SHA256.*X-Amz-Credential=[^&]+.*X-Amz-Date=[^&]+.*X-Amz-Expires=900.*X-Amz-SignedHeaders=host.*X-Amz-Signature=[A-Fa-f0-9]{64}.*$"
    );
    
    /**
     * Parse token and extract components.
     */
    static TokenComponents parseToken(String token) {
        if (token == null || token.isEmpty()) {
            return null;
        }
        
        // Extract endpoint:port prefix
        int queryStart = token.indexOf("/?");
        if (queryStart == -1) {
            return null;
        }
        
        String prefix = token.substring(0, queryStart);
        String[] parts = prefix.split(":");
        if (parts.length != 2) {
            return null;
        }
        
        TokenComponents components = new TokenComponents();
        components.endpoint = parts[0];
        components.port = Integer.parseInt(parts[1]);
        
        // Extract query parameters
        String queryString = token.substring(queryStart + 2);
        Map<String, String> params = parseQueryString(queryString);
        
        components.action = params.get("Action");
        components.algorithm = params.get("X-Amz-Algorithm");
        components.credential = params.get("X-Amz-Credential");
        components.date = params.get("X-Amz-Date");
        components.expires = params.get("X-Amz-Expires");
        components.signedHeaders = params.get("X-Amz-SignedHeaders");
        components.signature = params.get("X-Amz-Signature");
        
        return components;
    }
    
    /**
     * Parse query string into map.
     */
    private static Map<String, String> parseQueryString(String queryString) {
        Map<String, String> params = new HashMap<>();
        if (queryString == null || queryString.isEmpty()) {
            return params;
        }
        String[] pairs = queryString.split("&");
        for (String pair : pairs) {
            if (pair == null || pair.isEmpty()) {
                continue;
            }
            int eq = pair.indexOf("=");
            if (eq > 0) {
                try {
                    String key = URLDecoder.decode(pair.substring(0, eq), StandardCharsets.UTF_8);
                    String value = URLDecoder.decode(pair.substring(eq + 1), StandardCharsets.UTF_8);
                    params.put(key, value);
                } catch (Exception e) {
                    // If decoding fails, use raw values
                    String key = pair.substring(0, eq);
                    String value = pair.substring(eq + 1);
                    params.put(key, value);
                }
            }
        }
        return params;
    }
    
    /**
     * Validate token format matches expected pattern.
     * Checks for required components rather than exact pattern match.
     */
    static boolean isValidTokenFormat(String token) {
        if (token == null || token.isEmpty()) {
            return false;
        }
        
        // Check basic structure: endpoint:port/?query
        if (!token.matches("^[^:]+:\\d+/\\?.*")) {
            return false;
        }
        
        // Check for required query parameters (order doesn't matter)
        Map<String, String> params = extractQueryParameters(token);
        return params.containsKey("Action") &&
               params.containsKey("X-Amz-Algorithm") &&
               params.containsKey("X-Amz-Credential") &&
               params.containsKey("X-Amz-Date") &&
               params.containsKey("X-Amz-Expires") &&
               params.containsKey("X-Amz-SignedHeaders") &&
               params.containsKey("X-Amz-Signature") &&
               "DbConnect".equals(params.get("Action")) &&
               "AWS4-HMAC-SHA256".equals(params.get("X-Amz-Algorithm")) &&
               "900".equals(params.get("X-Amz-Expires")) &&
               "host".equals(params.get("X-Amz-SignedHeaders")) &&
               params.get("X-Amz-Signature") != null &&
               params.get("X-Amz-Signature").matches("[A-Fa-f0-9]{64}");
    }
    
    /**
     * Extract query parameters from token.
     */
    static Map<String, String> extractQueryParameters(String token) {
        int queryStart = token.indexOf("/?");
        if (queryStart == -1) {
            return new HashMap<>();
        }
        
        String queryString = token.substring(queryStart + 2);
        return parseQueryString(queryString);
    }
    
    /**
     * Verify signature parameters are present.
     */
    static boolean hasRequiredSignatureParameters(String token) {
        Map<String, String> params = extractQueryParameters(token);
        return params.containsKey("Action") &&
               params.containsKey("X-Amz-Algorithm") &&
               params.containsKey("X-Amz-Credential") &&
               params.containsKey("X-Amz-Date") &&
               params.containsKey("X-Amz-Expires") &&
               params.containsKey("X-Amz-SignedHeaders") &&
               params.containsKey("X-Amz-Signature");
    }
    
    /**
     * Create mock credentials for testing.
     */
    static AwsCredentials createMockCredentials(String accessKey, String secretKey) {
        return AwsBasicCredentials.create(accessKey, secretKey);
    }
    
    /**
     * Token components extracted from parsed token.
     */
    static class TokenComponents {
        String endpoint;
        int port;
        String action;
        String algorithm;
        String credential;
        String date;
        String expires;
        String signedHeaders;
        String signature;
        
        boolean isValid() {
            return endpoint != null && !endpoint.isEmpty() &&
                   port > 0 &&
                   "DbConnect".equals(action) &&
                   "AWS4-HMAC-SHA256".equals(algorithm) &&
                   credential != null && credential.contains("/dsql/aws4_request") &&
                   date != null && !date.isEmpty() &&
                   "900".equals(expires) &&
                   "host".equals(signedHeaders) &&
                   signature != null && signature.matches("[A-Fa-f0-9]{64}");
        }
    }
}
