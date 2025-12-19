package io.debezium.connector.dsql.auth;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import software.amazon.awssdk.auth.credentials.AwsCredentials;
import software.amazon.awssdk.regions.Region;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Map;
import java.util.TreeMap;

/**
 * Implements AWS Signature Version 4 query string authentication for DSQL.
 * 
 * This class manually implements SigV4 query string signing (similar to Python's SigV4QueryAuth)
 * to create presigned URLs for DSQL authentication. The signature is added to query parameters
 * rather than HTTP headers.
 * 
 * Reference: AWS Signature Version 4 Signing Process
 * https://docs.aws.amazon.com/general/latest/gr/sigv4_signing.html
 */
class SigV4QueryStringSigner {
    private static final Logger LOGGER = LoggerFactory.getLogger(SigV4QueryStringSigner.class);
    
    private static final String ALGORITHM = "AWS4-HMAC-SHA256";
    private static final String SERVICE = "dsql";
    private static final int EXPIRES_SECONDS = 900; // 15 minutes
    
    private static final DateTimeFormatter DATE_FORMATTER = DateTimeFormatter.ofPattern("yyyyMMdd")
            .withZone(ZoneOffset.UTC);
    private static final DateTimeFormatter TIMESTAMP_FORMATTER = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'")
            .withZone(ZoneOffset.UTC);
    
    /**
     * Generate a presigned URL query string for DSQL authentication.
     * 
     * @param endpoint DSQL endpoint hostname
     * @param port DSQL port (typically 5432)
     * @param credentials AWS credentials
     * @param region AWS region
     * @return Presigned query string with signature parameters
     */
    static String generatePresignedQueryString(String endpoint, int port, 
                                                AwsCredentials credentials, Region region) {
        try {
            Instant now = Instant.now();
            String dateStamp = DATE_FORMATTER.format(now);
            String timestamp = TIMESTAMP_FORMATTER.format(now);
            
            // Build query parameters (sorted for canonicalization)
            Map<String, String> queryParams = new TreeMap<>();
            queryParams.put("Action", "DbConnect");
            queryParams.put("X-Amz-Algorithm", ALGORITHM);
            queryParams.put("X-Amz-Credential", buildCredentialScope(credentials.accessKeyId(), dateStamp, region));
            queryParams.put("X-Amz-Date", timestamp);
            queryParams.put("X-Amz-Expires", String.valueOf(EXPIRES_SECONDS));
            queryParams.put("X-Amz-SignedHeaders", "host");
            
            // Create canonical request
            String canonicalRequest = createCanonicalRequest(endpoint, port, queryParams);
            LOGGER.debug("Canonical request: {}", canonicalRequest);
            
            // Create string to sign
            String stringToSign = createStringToSign(ALGORITHM, timestamp, dateStamp, region, canonicalRequest);
            LOGGER.debug("String to sign: {}", stringToSign);
            
            // Calculate signature
            String signature = calculateSignature(credentials.secretAccessKey(), dateStamp, region, stringToSign);
            
            // Add signature to query parameters
            queryParams.put("X-Amz-Signature", signature);
            
            // Build final query string
            StringBuilder queryString = new StringBuilder();
            boolean first = true;
            for (Map.Entry<String, String> entry : queryParams.entrySet()) {
                if (!first) {
                    queryString.append("&");
                }
                queryString.append(urlEncode(entry.getKey()))
                          .append("=")
                          .append(urlEncode(entry.getValue()));
                first = false;
            }
            
            return queryString.toString();
            
        } catch (Exception e) {
            LOGGER.error("Failed to generate presigned query string: {}", e.getMessage(), e);
            throw new RuntimeException("Failed to generate DSQL presigned query string", e);
        }
    }
    
    /**
     * Build credential scope string.
     * Format: {accessKeyId}/{date}/{region}/{service}/aws4_request
     */
    private static String buildCredentialScope(String accessKeyId, String dateStamp, Region region) {
        return String.format("%s/%s/%s/%s/aws4_request", 
                accessKeyId, dateStamp, region.id(), SERVICE);
    }
    
    /**
     * Create canonical request for SigV4 signing.
     * Format: METHOD\nURI\nQUERY_STRING\nHEADERS\n\nSIGNED_HEADERS\nPAYLOAD_HASH
     */
    private static String createCanonicalRequest(String endpoint, int port, Map<String, String> queryParams) {
        // HTTP method
        String method = "GET";
        
        // Canonical URI (just "/" for root)
        String canonicalUri = "/";
        
        // Canonical query string (sorted, URL encoded)
        StringBuilder canonicalQuery = new StringBuilder();
        boolean first = true;
        for (Map.Entry<String, String> entry : queryParams.entrySet()) {
            if (!first) {
                canonicalQuery.append("&");
            }
            canonicalQuery.append(urlEncode(entry.getKey()))
                         .append("=")
                         .append(urlEncode(entry.getValue()));
            first = false;
        }
        
        // Canonical headers (only host header for query string auth)
        String hostHeader = String.format("%s:%d", endpoint, port);
        String canonicalHeaders = String.format("host:%s\n", hostHeader);
        
        // Signed headers
        String signedHeaders = "host";
        
        // Payload hash (empty body for GET request)
        String payloadHash = sha256Hash("");
        
        // Combine all parts
        return String.format("%s\n%s\n%s\n%s\n%s\n%s",
                method, canonicalUri, canonicalQuery.toString(), 
                canonicalHeaders, signedHeaders, payloadHash);
    }
    
    /**
     * Create string to sign.
     * Format: ALGORITHM\nTIMESTAMP\nCREDENTIAL_SCOPE\nCANONICAL_REQUEST_HASH
     */
    private static String createStringToSign(String algorithm, String timestamp, String dateStamp,
                                             Region region, String canonicalRequest) {
        String credentialScope = String.format("%s/%s/%s/aws4_request", dateStamp, region.id(), SERVICE);
        String canonicalRequestHash = sha256Hash(canonicalRequest);
        
        return String.format("%s\n%s\n%s\n%s",
                algorithm, timestamp, credentialScope, canonicalRequestHash);
    }
    
    /**
     * Calculate the final signature using HMAC-SHA256.
     */
    private static String calculateSignature(String secretAccessKey, String dateStamp, 
                                             Region region, String stringToSign) {
        try {
            // kDate = HMAC("AWS4" + secretKey, dateStamp)
            byte[] kDate = hmacSha256(("AWS4" + secretAccessKey).getBytes(StandardCharsets.UTF_8), dateStamp);
            
            // kRegion = HMAC(kDate, region)
            byte[] kRegion = hmacSha256(kDate, region.id());
            
            // kService = HMAC(kRegion, service)
            byte[] kService = hmacSha256(kRegion, SERVICE);
            
            // kSigning = HMAC(kService, "aws4_request")
            byte[] kSigning = hmacSha256(kService, "aws4_request");
            
            // signature = HMAC(kSigning, stringToSign)
            byte[] signature = hmacSha256(kSigning, stringToSign);
            
            // Convert to hex string
            return bytesToHex(signature);
            
        } catch (Exception e) {
            throw new RuntimeException("Failed to calculate signature", e);
        }
    }
    
    /**
     * Compute HMAC-SHA256.
     */
    private static byte[] hmacSha256(byte[] key, String data) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            SecretKeySpec secretKeySpec = new SecretKeySpec(key, "HmacSHA256");
            mac.init(secretKeySpec);
            return mac.doFinal(data.getBytes(StandardCharsets.UTF_8));
        } catch (Exception e) {
            throw new RuntimeException("Failed to compute HMAC-SHA256", e);
        }
    }
    
    /**
     * Compute SHA-256 hash.
     */
    private static String sha256Hash(String data) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(data.getBytes(StandardCharsets.UTF_8));
            return bytesToHex(hash);
        } catch (Exception e) {
            throw new RuntimeException("Failed to compute SHA-256 hash", e);
        }
    }
    
    /**
     * Convert bytes to hexadecimal string.
     */
    private static String bytesToHex(byte[] bytes) {
        StringBuilder hex = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) {
            hex.append(String.format("%02x", b));
        }
        return hex.toString();
    }
    
    /**
     * URL encode a string (RFC 3986).
     */
    private static String urlEncode(String value) {
        try {
            return URLEncoder.encode(value, StandardCharsets.UTF_8.toString())
                    .replace("+", "%20")  // Replace + with %20 for space
                    .replace("*", "%2A")  // Replace * with %2A
                    .replace("%7E", "~"); // Replace %7E with ~ (tilde should not be encoded)
        } catch (Exception e) {
            throw new RuntimeException("Failed to URL encode: " + value, e);
        }
    }
}
