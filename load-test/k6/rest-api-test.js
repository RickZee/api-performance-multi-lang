/**
 * k6 REST API Throughput Test
 * Tests REST APIs (producer-api-java-rest, producer-api-rust-rest, producer-api-go-rest)
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';
import { generateEventPayload } from './shared/helpers.js';
import { getTestOptions } from './config.js';

// Custom metrics
const errorRate = new Rate('errors');

// Test configuration
export const options = getTestOptions();

// Get API configuration from environment
const apiHost = __ENV.HOST || 'producer-api-java-rest';
const apiPort = __ENV.PORT || 8081;
const apiPath = __ENV.PATH || '/api/v1/events';
const apiUrl = `http://${apiHost}:${apiPort}${apiPath}`;

export default function () {
    // Generate event payload
    const payload = generateEventPayload();
    
    // Set headers
    const params = {
        headers: {
            'Content-Type': 'application/json',
        },
    };
    
    // Send POST request
    const res = http.post(apiUrl, payload, params);
    
    // Check response
    const success = check(res, {
        'status is 200': (r) => r.status === 200,
        'response time < 5s': (r) => r.timings.duration < 5000,
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
    summary += `${indent}Test Summary\n`;
    summary += `${indent}============\n\n`;
    
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
    
    summary += '\n';
    return summary;
}

