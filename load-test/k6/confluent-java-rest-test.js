/**
 * k6 Test Script for Java REST API to Confluent Integration
 * 
 * This script sends events to the Java REST producer API, which saves them to PostgreSQL.
 * The Debezium CDC connector captures these changes and streams them to Confluent Cloud.
 * 
 * Flow: k6 → Java REST API → PostgreSQL → Debezium CDC → Confluent Cloud
 * 
 * Usage:
 *   k6 run --env HOST=localhost --env PORT=8081 --env ENDPOINT=/api/v1/events confluent-java-rest-test.js
 *   k6 run --env HOST=localhost --env PORT=8081 --env ENDPOINT=/api/v1/events/events-simple confluent-java-rest-test.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';
import { generateEventPayload, generateSimpleEventPayload } from './shared/helpers.js';
import { getTestOptions } from './config.js';

// Custom metrics
const errorRate = new Rate('errors');

// Test configuration
export const options = getTestOptions();

// Get API configuration from environment
const apiHost = __ENV.HOST || 'localhost';
const apiPort = __ENV.PORT || 8081;
const apiEndpoint = __ENV.ENDPOINT || '/api/v1/events';
const apiUrl = `http://${apiHost}:${apiPort}${apiEndpoint}`;

// Determine if we're using simple events endpoint
const isSimpleEventsEndpoint = apiEndpoint === '/api/v1/events/events-simple' || 
                                apiEndpoint.endsWith('/events-simple');

// Authentication configuration
const AUTH_ENABLED = __ENV.AUTH_ENABLED === 'true' || __ENV.AUTH_ENABLED === '1';
const JWT_TOKEN = __ENV.JWT_TOKEN || '';

// Payload size is configured via PAYLOAD_SIZE environment variable (4k, 8k, 32k, 64k)
// Only applies to full events endpoint, not simple events
// If not specified, uses default small payload (~400-500 bytes)

export default function () {
    // Generate event payload based on endpoint type
    let payload;
    if (isSimpleEventsEndpoint) {
        payload = generateSimpleEventPayload();
    } else {
        payload = generateEventPayload();
    }
    
    // Set headers
    const headers = {
        'Content-Type': 'application/json',
    };
    
    // Add Authorization header if auth is enabled
    if (AUTH_ENABLED && JWT_TOKEN) {
        headers['Authorization'] = `Bearer ${JWT_TOKEN}`;
    }
    
    const params = {
        headers: headers,
    };
    
    // Send POST request
    const res = http.post(apiUrl, payload, params);
    
    // Check response
    const success = check(res, {
        'status is 200': (r) => r.status === 200,
        'response time < 5s': (r) => r.timings.duration < 5000,
        'response body contains success': (r) => {
            const body = r.body || '';
            return body.includes('successfully') || body.includes('processed');
        },
    });
    
    errorRate.add(!success);
    
    // Small sleep to avoid overwhelming the server
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
    summary += `${indent}========================================\n`;
    summary += `${indent}k6 Confluent Integration Test Summary\n`;
    summary += `${indent}========================================\n\n`;
    summary += `${indent}API Endpoint: ${apiUrl}\n`;
    summary += `${indent}Endpoint Type: ${isSimpleEventsEndpoint ? 'Simple Events' : 'Full Events'}\n`;
    summary += `${indent}========================================\n\n`;
    
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
    
    if (data.metrics.errors) {
        const errors = data.metrics.errors;
        summary += `${indent}Errors: ${errors.values.rate.toFixed(4)} (${(errors.values.rate * 100).toFixed(2)}%)\n`;
    }
    
    summary += '\n';
    summary += `${indent}Next Steps:\n`;
    summary += `${indent}  1. Verify events in PostgreSQL database\n`;
    summary += `${indent}  2. Check Debezium CDC connector status\n`;
    summary += `${indent}  3. Verify events in Confluent Cloud topics\n`;
    summary += `${indent}  4. Run verification script: cdc-streaming/scripts/verify-k6-events-in-confluent.sh\n`;
    summary += '\n';
    
    return summary;
}
