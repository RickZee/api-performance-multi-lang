/**
 * k6 Lambda REST API Throughput Test
 * Tests Lambda REST APIs via API Gateway HTTP API
 * Supports: producer-api-go-rest-lambda, producer-api-java-rest-lambda
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';
import { generateEventPayload } from './shared/helpers.js';
import { getTestOptions } from './config.js';

// Custom metrics
const errorRate = new Rate('errors');
const coldStartRate = new Rate('cold_starts');

// Test configuration
export const options = getTestOptions();

// Get API configuration from environment
// For Lambda APIs, we use API Gateway HTTP API endpoints (HTTP for local, HTTPS for AWS)
// Priority: API_URL > LAMBDA_API_URL > default
// Note: Use API_PATH instead of PATH to avoid conflict with system PATH variable
const apiUrl = __ENV.API_URL || __ENV.LAMBDA_API_URL || 'http://localhost:9084';
const apiPath = __ENV.API_PATH || '/api/v1/events';

// Construct full URL if only base URL provided
let fullApiUrl = apiUrl;
if (!apiUrl.includes('/api/v1/events')) {
    // Remove trailing slash if present
    const baseUrl = apiUrl.replace(/\/$/, '');
    fullApiUrl = `${baseUrl}${apiPath}`;
}

// Payload size is configured via PAYLOAD_SIZE environment variable (4k, 8k, 32k, 64k)
// If not specified, uses default small payload (~400-500 bytes)

// Track cold starts by detecting higher latency on first request
// Cold starts typically have much higher latency (>500ms for Go, >1000ms for Java)
const COLD_START_THRESHOLD_MS = 500; // Threshold to detect potential cold starts

export default function () {
    // Generate event payload (size controlled by PAYLOAD_SIZE env var)
    const payload = generateEventPayload();
    
    // Set headers for API Gateway HTTP API
    const params = {
        headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
        },
        tags: {
            name: 'Lambda REST API',
        },
    };
    
    // Send POST request
    const res = http.post(fullApiUrl, payload, params);
    
    // Detect potential cold start (high latency on first request)
    // Note: This is a heuristic - actual cold start detection should be done via CloudWatch Logs
    const isPotentialColdStart = res.timings.duration > COLD_START_THRESHOLD_MS;
    if (isPotentialColdStart) {
        coldStartRate.add(1);
    } else {
        coldStartRate.add(0);
    }
    
    // Check response
    const success = check(res, {
        'status is 200': (r) => r.status === 200,
        'response time < 30s': (r) => r.timings.duration < 30000, // Lambda timeout is typically 30s
        'response has body': (r) => r.body && r.body.length > 0,
    });
    
    errorRate.add(!success);
    
    // Small sleep to avoid overwhelming the API Gateway
    sleep(0.1);
}

export function handleSummary(data) {
    return {
        'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    };
}

function textSummary(data, options) {
    const indent = options.indent || '';
    const enableColors = options.enableColors || false;
    
    let summary = '\n';
    summary += `${indent}Lambda REST API Test Summary\n`;
    summary += `${indent}===========================\n\n`;
    
    // HTTP metrics
    if (data.metrics.http_reqs) {
        const httpReqs = data.metrics.http_reqs;
        summary += `${indent}HTTP Requests:\n`;
        summary += `${indent}  Total: ${httpReqs.values.count}\n`;
        summary += `${indent}  Rate: ${httpReqs.values.rate.toFixed(2)} req/s\n`;
    }
    
    if (data.metrics.http_req_duration) {
        const duration = data.metrics.http_req_duration;
        summary += `${indent}Response Time:\n`;
        if (duration.values) {
            if (duration.values.avg !== undefined) {
                summary += `${indent}  Avg: ${duration.values.avg.toFixed(2)}ms\n`;
            }
            if (duration.values.min !== undefined) {
                summary += `${indent}  Min: ${duration.values.min.toFixed(2)}ms\n`;
            }
            if (duration.values.max !== undefined) {
                summary += `${indent}  Max: ${duration.values.max.toFixed(2)}ms\n`;
            }
            if (duration.values['p(95)'] !== undefined) {
                summary += `${indent}  P95: ${duration.values['p(95)'].toFixed(2)}ms\n`;
            }
            if (duration.values['p(99)'] !== undefined) {
                summary += `${indent}  P99: ${duration.values['p(99)'].toFixed(2)}ms\n`;
            }
        }
    }
    
    if (data.metrics.http_req_failed) {
        const failed = data.metrics.http_req_failed;
        summary += `${indent}Error Rate: ${(failed.values.rate * 100).toFixed(2)}%\n`;
    }
    
    // Cold start detection (heuristic)
    if (data.metrics.cold_starts) {
        const coldStarts = data.metrics.cold_starts;
        summary += `${indent}Potential Cold Starts: ${coldStarts.values.count} (${(coldStarts.values.rate * 100).toFixed(2)}%)\n`;
        summary += `${indent}  Note: Actual cold starts should be verified via CloudWatch Logs\n`;
    }
    
    summary += '\n';
    return summary;
}
