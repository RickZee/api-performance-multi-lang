package com.example.metadata.testutil;

import com.sun.net.httpserver.HttpServer;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpExchange;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.stream.Collectors;

/**
 * Mock Jenkins HTTP server for integration testing.
 * 
 * This server simulates Jenkins build trigger endpoints and captures
 * build requests for verification in tests.
 */
public class MockJenkinsServer {
    
    private HttpServer server;
    private final List<BuildRequest> capturedRequests = new CopyOnWriteArrayList<>();
    private int port;
    private boolean simulateFailure = false;
    private int failureStatusCode = 500;
    private boolean simulateTimeout = false;
    private String expectedUsername;
    private String expectedToken;
    private String expectedBuildToken;
    
    /**
     * Represents a captured Jenkins build request.
     */
    public static class BuildRequest {
        private final String jobName;
        private final Map<String, String> parameters;
        private final String authMethod;
        private final long timestamp;
        
        public BuildRequest(String jobName, Map<String, String> parameters, String authMethod) {
            this.jobName = jobName;
            this.parameters = new HashMap<>(parameters);
            this.authMethod = authMethod;
            this.timestamp = System.currentTimeMillis();
        }
        
        public String getJobName() {
            return jobName;
        }
        
        public Map<String, String> getParameters() {
            return Collections.unmodifiableMap(parameters);
        }
        
        public String getAuthMethod() {
            return authMethod;
        }
        
        public long getTimestamp() {
            return timestamp;
        }
        
        public String getFilterEventType() {
            return parameters.get("FILTER_EVENT_TYPE");
        }
        
        public String getFilterId() {
            return parameters.get("FILTER_ID");
        }
        
        public String getFilterVersion() {
            return parameters.get("FILTER_VERSION");
        }
        
        @Override
        public String toString() {
            return String.format("BuildRequest{jobName='%s', parameters=%s, authMethod='%s', timestamp=%d}",
                    jobName, parameters, authMethod, timestamp);
        }
    }
    
    /**
     * Starts the mock Jenkins server on a random available port.
     * 
     * @return The port the server is listening on
     * @throws IOException if the server cannot be started
     */
    public int start() throws IOException {
        return start(0); // 0 means use any available port
    }
    
    /**
     * Starts the mock Jenkins server on the specified port.
     * 
     * @param port The port to listen on (0 for any available port)
     * @return The port the server is actually listening on
     * @throws IOException if the server cannot be started
     */
    public int start(int port) throws IOException {
        if (server != null) {
            throw new IllegalStateException("Server is already running");
        }
        
        server = HttpServer.create(new InetSocketAddress(port), 0);
        this.port = server.getAddress().getPort();
        
        // Handle /job/{jobName}/build endpoint (standard Jenkins build endpoint)
        server.createContext("/job/", new BuildHandler());
        
        // Handle build token endpoint (alternative authentication)
        server.createContext("/buildByToken/build", new BuildTokenHandler());
        
        server.setExecutor(null); // Use default executor
        server.start();
        
        return this.port;
    }
    
    /**
     * Stops the mock Jenkins server.
     */
    public void stop() {
        if (server != null) {
            server.stop(0);
            server = null;
        }
    }
    
    /**
     * Gets the port the server is listening on.
     * 
     * @return The port number
     */
    public int getPort() {
        return port;
    }
    
    /**
     * Gets the base URL of the server.
     * 
     * @return The base URL (e.g., "http://localhost:8080")
     */
    public String getBaseUrl() {
        return "http://localhost:" + port;
    }
    
    /**
     * Gets all captured build requests.
     * 
     * @return List of captured build requests
     */
    public List<BuildRequest> getCapturedRequests() {
        return new ArrayList<>(capturedRequests);
    }
    
    /**
     * Gets captured requests for a specific event type.
     * 
     * @param eventType The event type to filter by
     * @return List of matching build requests
     */
    public List<BuildRequest> getCapturedRequests(String eventType) {
        return capturedRequests.stream()
                .filter(req -> eventType.equals(req.getFilterEventType()))
                .collect(Collectors.toList());
    }
    
    /**
     * Clears all captured requests.
     */
    public void reset() {
        capturedRequests.clear();
    }
    
    /**
     * Configures the server to simulate failures.
     * 
     * @param simulateFailure Whether to simulate failures
     * @param statusCode The HTTP status code to return (default: 500)
     */
    public void setSimulateFailure(boolean simulateFailure, int statusCode) {
        this.simulateFailure = simulateFailure;
        this.failureStatusCode = statusCode;
    }
    
    /**
     * Configures the server to simulate timeouts.
     * 
     * @param simulateTimeout Whether to simulate timeouts
     */
    public void setSimulateTimeout(boolean simulateTimeout) {
        this.simulateTimeout = simulateTimeout;
    }
    
    /**
     * Sets expected authentication credentials.
     * 
     * @param username Expected username
     * @param token Expected API token
     */
    public void setExpectedAuth(String username, String token) {
        this.expectedUsername = username;
        this.expectedToken = token;
    }
    
    /**
     * Sets expected build token.
     * 
     * @param buildToken Expected build token
     */
    public void setExpectedBuildToken(String buildToken) {
        this.expectedBuildToken = buildToken;
    }
    
    /**
     * Verifies that a build request was captured for the given event type.
     * 
     * @param eventType The event type to check
     * @return true if a request was captured, false otherwise
     */
    public boolean wasTriggered(String eventType) {
        return !getCapturedRequests(eventType).isEmpty();
    }
    
    /**
     * Verifies that a build request was captured with the given parameters.
     * 
     * @param eventType Expected event type
     * @param filterId Expected filter ID
     * @param filterVersion Expected filter version
     * @return true if a matching request was captured, false otherwise
     */
    public boolean wasTriggeredWith(String eventType, String filterId, String filterVersion) {
        return capturedRequests.stream()
                .anyMatch(req -> eventType.equals(req.getFilterEventType())
                        && filterId.equals(req.getFilterId())
                        && filterVersion.equals(req.getFilterVersion()));
    }
    
    /**
     * Handler for /job/{jobName}/build endpoint (standard Jenkins build endpoint).
     * Handles both /build and /buildWithParameters.
     */
    private class BuildHandler implements HttpHandler {
        @Override
        public void handle(HttpExchange exchange) throws IOException {
            if (!"POST".equals(exchange.getRequestMethod())) {
                sendResponse(exchange, 405, "Method Not Allowed");
                return;
            }
            
            // Simulate timeout if configured
            if (simulateTimeout) {
                try {
                    Thread.sleep(60000); // Sleep for 60 seconds to simulate timeout
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            }
            
            // Check authentication (allow if no auth expected)
            String authMethod = checkAuthentication(exchange);
            if (authMethod == null && (expectedUsername != null || expectedToken != null || expectedBuildToken != null)) {
                sendResponse(exchange, 401, "Unauthorized");
                return;
            }
            if (authMethod == null) {
                authMethod = "no-auth";
            }
            
            // Parse job name from path: /job/{jobName}/build or /job/{jobName}/buildWithParameters
            String path = exchange.getRequestURI().getPath();
            String[] pathParts = path.split("/");
            if (pathParts.length < 4 || !"job".equals(pathParts[1]) 
                || (!"build".equals(pathParts[pathParts.length - 1]) 
                    && !"buildWithParameters".equals(pathParts[pathParts.length - 1]))) {
                sendResponse(exchange, 404, "Not Found");
                return;
            }
            
            String jobName = pathParts[2];
            
            // Parse parameters from request body (form-encoded JSON or form data)
            Map<String, String> parameters = parseFormParameters(exchange);
            
            // If parameters are in JSON format (Jenkins parameterized build format)
            if (parameters.containsKey("json")) {
                parameters = parseJsonParameters(parameters.get("json"));
            }
            
            // Capture the request
            BuildRequest request = new BuildRequest(jobName, parameters, authMethod);
            capturedRequests.add(request);
            
            // Simulate failure if configured
            if (simulateFailure) {
                sendResponse(exchange, failureStatusCode, "Internal Server Error");
                return;
            }
            
            // Return success
            sendResponse(exchange, 201, "Created");
        }
    }
    
    /**
     * Handler for /buildByToken/build endpoint (build token authentication).
     */
    private class BuildTokenHandler implements HttpHandler {
        @Override
        public void handle(HttpExchange exchange) throws IOException {
            if (!"POST".equals(exchange.getRequestMethod())) {
                sendResponse(exchange, 405, "Method Not Allowed");
                return;
            }
            
            // Check build token
            String query = exchange.getRequestURI().getQuery();
            if (query == null || !query.contains("token=" + expectedBuildToken)) {
                sendResponse(exchange, 403, "Forbidden");
                return;
            }
            
            // Parse parameters from query string
            Map<String, String> parameters = parseQueryParameters(query);
            
            // Capture the request
            BuildRequest request = new BuildRequest("default", parameters, "build-token");
            capturedRequests.add(request);
            
            // Simulate failure if configured
            if (simulateFailure) {
                sendResponse(exchange, failureStatusCode, "Internal Server Error");
                return;
            }
            
            // Return success
            sendResponse(exchange, 201, "Created");
        }
    }
    
    /**
     * Checks authentication from the request.
     * 
     * @param exchange The HTTP exchange
     * @return The authentication method used, or null if authentication failed
     */
    private String checkAuthentication(HttpExchange exchange) {
        // Check Basic Auth header
        List<String> authHeaders = exchange.getRequestHeaders().get("Authorization");
        if (authHeaders != null && !authHeaders.isEmpty()) {
            String authHeader = authHeaders.get(0);
            if (authHeader.startsWith("Basic ")) {
                String credentials = authHeader.substring(6);
                String decoded = new String(Base64.getDecoder().decode(credentials), StandardCharsets.UTF_8);
                String[] parts = decoded.split(":", 2);
                if (parts.length == 2) {
                    String username = parts[0];
                    String password = parts[1];
                    if (expectedUsername != null && expectedToken != null
                            && expectedUsername.equals(username) && expectedToken.equals(password)) {
                        return "basic-auth";
                    }
                }
            }
        }
        
        // If no auth expected, allow the request
        if (expectedUsername == null && expectedToken == null && expectedBuildToken == null) {
            return "no-auth";
        }
        
        return null;
    }
    
    /**
     * Parses form-encoded parameters from the request body.
     * 
     * @param exchange The HTTP exchange
     * @return Map of parameter names to values
     */
    private Map<String, String> parseFormParameters(HttpExchange exchange) throws IOException {
        Map<String, String> parameters = new HashMap<>();
        
        // Read request body
        String body = new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
        
        // Parse form-encoded data
        if (body != null && !body.isEmpty()) {
            String[] pairs = body.split("&");
            for (String pair : pairs) {
                String[] keyValue = pair.split("=", 2);
                if (keyValue.length == 2) {
                    String key = java.net.URLDecoder.decode(keyValue[0], StandardCharsets.UTF_8);
                    String value = java.net.URLDecoder.decode(keyValue[1], StandardCharsets.UTF_8);
                    parameters.put(key, value);
                }
            }
        }
        
        return parameters;
    }
    
    /**
     * Parses query parameters from the query string.
     * 
     * @param query The query string
     * @return Map of parameter names to values
     */
    private Map<String, String> parseQueryParameters(String query) {
        Map<String, String> parameters = new HashMap<>();
        
        String[] pairs = query.split("&");
        for (String pair : pairs) {
            String[] keyValue = pair.split("=", 2);
            if (keyValue.length == 2) {
                String key = java.net.URLDecoder.decode(keyValue[0], StandardCharsets.UTF_8);
                String value = java.net.URLDecoder.decode(keyValue[1], StandardCharsets.UTF_8);
                parameters.put(key, value);
            }
        }
        
        return parameters;
    }
    
    /**
     * Parses JSON parameters from Jenkins parameterized build format.
     * Format: {"parameter":[{"name":"FILTER_EVENT_TYPE","value":"create"},...]}
     * 
     * @param jsonString The JSON string (may be URL encoded)
     * @return Map of parameter names to values
     */
    private Map<String, String> parseJsonParameters(String jsonString) {
        Map<String, String> parameters = new HashMap<>();
        
        try {
            // URL decode if needed
            String decoded = java.net.URLDecoder.decode(jsonString, StandardCharsets.UTF_8);
            
            // Simple JSON parsing for parameter array
            // Look for "parameter":[{...}]
            int paramStart = decoded.indexOf("\"parameter\":[");
            if (paramStart == -1) {
                return parameters;
            }
            
            int arrayStart = decoded.indexOf("[", paramStart) + 1;
            int arrayEnd = decoded.lastIndexOf("]");
            
            if (arrayStart > 0 && arrayEnd > arrayStart) {
                String paramArray = decoded.substring(arrayStart, arrayEnd);
                
                // Parse each parameter object: {"name":"...","value":"..."}
                int pos = 0;
                while (pos < paramArray.length()) {
                    int objStart = paramArray.indexOf("{", pos);
                    if (objStart == -1) break;
                    
                    int objEnd = paramArray.indexOf("}", objStart);
                    if (objEnd == -1) break;
                    
                    String paramObj = paramArray.substring(objStart, objEnd + 1);
                    
                    // Extract name and value
                    String name = extractJsonValue(paramObj, "name");
                    String value = extractJsonValue(paramObj, "value");
                    
                    if (name != null && value != null) {
                        parameters.put(name, value);
                    }
                    
                    pos = objEnd + 1;
                }
            }
        } catch (Exception e) {
            // If parsing fails, return empty map
        }
        
        return parameters;
    }
    
    /**
     * Extracts a JSON value from a JSON object string.
     * 
     * @param json The JSON object string
     * @param key The key to extract
     * @return The value, or null if not found
     */
    private String extractJsonValue(String json, String key) {
        String pattern = "\"" + key + "\":\"";
        int start = json.indexOf(pattern);
        if (start == -1) {
            return null;
        }
        
        start += pattern.length();
        int end = json.indexOf("\"", start);
        if (end == -1) {
            return null;
        }
        
        return json.substring(start, end);
    }
    
    /**
     * Sends an HTTP response.
     * 
     * @param exchange The HTTP exchange
     * @param statusCode The HTTP status code
     * @param message The response message
     */
    private void sendResponse(HttpExchange exchange, int statusCode, String message) throws IOException {
        exchange.getResponseHeaders().set("Content-Type", "text/plain");
        exchange.sendResponseHeaders(statusCode, message.length());
        try (OutputStream os = exchange.getResponseBody()) {
            os.write(message.getBytes(StandardCharsets.UTF_8));
        }
    }
}

