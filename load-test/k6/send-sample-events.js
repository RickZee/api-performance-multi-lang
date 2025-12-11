/**
 * k6 Script to Send Sample Events to Java REST API
 * 
 * Sends 4 specific event types based on samples in data/schemas/event/samples/:
 * 1. Car Created
 * 2. Loan Created  
 * 3. Loan Payment Submitted
 * 4. Car Service Done
 * 
 * Flow: k6 → Python REST Lambda API → Aurora RDS PostgreSQL
 * 
 * Usage:
 *   k6 run --env HOST=localhost --env PORT=8081 send-sample-events.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';
import { randomString, randomIntBetween } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';

// Custom metrics
const errorRate = new Rate('errors');
const eventsSent = new Rate('events_sent');

// Test configuration - send each event type once
export const options = {
    vus: 1,
    iterations: 4, // One iteration per event type
};

// Get API configuration from environment
// Support both full URL (for Lambda API Gateway) and host/port (for local)
const apiUrl = __ENV.API_URL || (() => {
    const apiHost = __ENV.HOST || 'localhost';
    const apiPort = __ENV.PORT || 8081;
    return `http://${apiHost}:${apiPort}/api/v1/events`;
})();

// Authentication configuration
const AUTH_ENABLED = __ENV.AUTH_ENABLED === 'true' || __ENV.AUTH_ENABLED === '1';
const JWT_TOKEN = __ENV.JWT_TOKEN || '';

// Generate UUID
function generateUUID() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
        const r = Math.random() * 16 | 0;
        const v = c === 'x' ? r : (r & 0x3 | 0x8);
        return v.toString(16);
    });
}

// Generate ISO 8601 timestamp
function generateTimestamp() {
    return new Date().toISOString();
}

// Generate event payloads based on samples
function generateCarCreatedEvent() {
    const timestamp = generateTimestamp();
    const carId = `CAR-${new Date().toISOString().split('T')[0].replace(/-/g, '')}-${randomIntBetween(1, 999)}`;
    const uuid = generateUUID();
    
    return JSON.stringify({
        eventHeader: {
            uuid: uuid,
            eventName: "Car Created",
            eventType: "CarCreated",
            createdDate: timestamp,
            savedDate: timestamp
        },
        eventBody: {
            entities: [{
            entityType: "Car",
            entityId: carId,
            updatedAttributes: {
            id: carId,
            vin: `${randomString(17).toUpperCase()}`,
            make: ["Tesla", "Toyota", "Honda", "Ford", "BMW"][randomIntBetween(0, 4)],
            model: ["Model S", "Camry", "Accord", "F-150", "3 Series"][randomIntBetween(0, 4)],
            year: randomIntBetween(2020, 2025),
            color: ["Midnight Silver", "Pearl White", "Deep Blue", "Red", "Black"][randomIntBetween(0, 4)],
            mileage: randomIntBetween(0, 50000),
            lastServiceDate: timestamp,
            totalBalance: 0.0,
            lastLoanPaymentDate: timestamp,
            owner: `${randomString(8)} ${randomString(10)}`
            }
            }]
        }
    });
}

function generateLoanCreatedEvent(carId) {
    const timestamp = generateTimestamp();
    const loanId = `LOAN-${new Date().toISOString().split('T')[0].replace(/-/g, '')}-${randomIntBetween(1, 999)}`;
    const uuid = generateUUID();
    const loanAmount = randomIntBetween(20000, 80000);
    const interestRate = (Math.random() * 0.05 + 0.02).toFixed(4); // 2-7% APR
    const termMonths = [36, 48, 60, 72][randomIntBetween(0, 3)];
    const monthlyPayment = (loanAmount * (interestRate / 12) * Math.pow(1 + interestRate / 12, termMonths)) / 
                           (Math.pow(1 + interestRate / 12, termMonths) - 1);
    
    return JSON.stringify({
        eventHeader: {
            uuid: uuid,
            eventName: "Loan Created",
            eventType: "LoanCreated",
            createdDate: timestamp,
            savedDate: timestamp
        },
        eventBody: {
            entities: [{
            entityType: "Loan",
            entityId: loanId,
            updatedAttributes: {
            id: loanId,
            carId: carId,
            financialInstitution: ["First National Bank", "Chase Bank", "Wells Fargo", "Bank of America"][randomIntBetween(0, 3)],
            balance: loanAmount.toFixed(2),
            lastPaidDate: timestamp,
            loanAmount: loanAmount.toFixed(2),
            interestRate: parseFloat(interestRate),
            termMonths: termMonths,
            startDate: timestamp,
            status: "active",
            monthlyPayment: monthlyPayment.toFixed(2)
            }
            }]
        }
    });
}

function generateLoanPaymentEvent(loanId, amount) {
    const timestamp = generateTimestamp();
    const paymentId = `PAYMENT-${new Date().toISOString().split('T')[0].replace(/-/g, '')}-${randomIntBetween(1, 999)}`;
    const uuid = generateUUID();
    
    return JSON.stringify({
        eventHeader: {
            uuid: uuid,
            eventName: "Loan Payment Submitted",
            eventType: "LoanPaymentSubmitted",
            createdDate: timestamp,
            savedDate: timestamp
        },
        eventBody: {
            entities: [{
            entityType: "LoanPayment",
            entityId: paymentId,
            updatedAttributes: {
            id: paymentId,
            loanId: loanId,
            amount: parseFloat(amount).toFixed(2),
            paymentDate: timestamp
            }
            }]
        }
    });
}

function generateCarServiceDoneEvent(carId, serviceId = null) {
    const timestamp = generateTimestamp();
    const id = serviceId || `SERVICE-${new Date().toISOString().split('T')[0].replace(/-/g, '')}-${randomIntBetween(1, 999)}`;
    const uuid = generateUUID();
    const amountPaid = (100 + Math.random() * 1000).toFixed(2); // $100-$1100
    const mileageAtService = randomIntBetween(1000, 100000);
    const dealers = [
        "Tesla Service Center - San Francisco",
        "Toyota Service Center - Los Angeles",
        "Honda Service Center - New York",
        "Ford Service Center - Chicago",
        "BMW Service Center - Miami"
    ];
    const dealerId = `DEALER-${randomIntBetween(1, 999)}`;
    const dealerName = dealers[randomIntBetween(0, dealers.length - 1)];
    const descriptions = [
        "Regular maintenance service including tire rotation, brake inspection, and fluid top-up",
        "Oil change and filter replacement",
        "Brake pad replacement and brake fluid flush",
        "Transmission service and fluid change",
        "Battery replacement and electrical system check"
    ];
    const description = descriptions[randomIntBetween(0, descriptions.length - 1)];
    
    return JSON.stringify({
        eventHeader: {
            uuid: uuid,
            eventName: "Car Service Done",
            eventType: "CarServiceDone",
            createdDate: timestamp,
            savedDate: timestamp
        },
        eventBody: {
            entities: [{
                entityType: "ServiceRecord",
                entityId: id,
                updatedAttributes: {
                    id: id,
                    carId: carId,
                    serviceDate: timestamp,
                    amountPaid: parseFloat(amountPaid).toFixed(2),
                    dealerId: dealerId,
                    dealerName: dealerName,
                    mileageAtService: mileageAtService,
                    description: description
                }
            }]
        }
    });
}

// Use setup function to generate linked IDs once
let sharedData = {};

export function setup() {
    // Generate IDs that will be used across iterations
    const timestamp = new Date().toISOString().split('T')[0].replace(/-/g, '');
    const carId = `CAR-${timestamp}-${Math.floor(Math.random() * 1000)}`;
    const loanId = `LOAN-${timestamp}-${Math.floor(Math.random() * 1000)}`;
    const serviceId = `SERVICE-${timestamp}-${Math.floor(Math.random() * 1000)}`;
    const monthlyPayment = (500 + Math.random() * 1500).toFixed(2); // $500-$2000
    
    return {
        carId: carId,
        loanId: loanId,
        serviceId: serviceId,
        monthlyPayment: monthlyPayment
    };
}

export default function (data) {
    const iteration = __ITER; // Current iteration (0, 1, 2, 3)
    let payload;
    let eventType;
    
    // Generate events in sequence: Car → Loan → Payment → Service
    if (iteration === 0) {
        // First iteration: Car Created
        payload = generateCarCreatedEvent();
        // Override with shared car ID for consistency
        const carEvent = JSON.parse(payload);
        carEvent.eventBody.entities[0].entityId = data.carId;
        carEvent.eventBody.entities[0].updatedAttributes.id = data.carId;
        payload = JSON.stringify(carEvent);
        eventType = "CarCreated";
    } else if (iteration === 1) {
        // Second iteration: Loan Created (linked to car)
        payload = generateLoanCreatedEvent(data.carId);
        // Override with shared loan ID for consistency
        const loanEvent = JSON.parse(payload);
        loanEvent.eventBody.entities[0].entityId = data.loanId;
        loanEvent.eventBody.entities[0].updatedAttributes.id = data.loanId;
        payload = JSON.stringify(loanEvent);
        eventType = "LoanCreated";
    } else if (iteration === 2) {
        // Third iteration: Loan Payment (linked to loan)
        payload = generateLoanPaymentEvent(data.loanId, data.monthlyPayment);
        eventType = "LoanPaymentSubmitted";
    } else {
        // Fourth iteration: Car Service Done (linked to car)
        payload = generateCarServiceDoneEvent(data.carId, data.serviceId);
        eventType = "CarServiceDone";
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
    eventsSent.add(success);
    
    // Log event type
    console.log(`Sent ${eventType} event (iteration ${iteration + 1}/4)`);
    
    // Small delay between events to ensure proper sequencing
    sleep(1);
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
    summary += `${indent}k6 Sample Events Test Summary\n`;
    summary += `${indent}========================================\n\n`;
    summary += `${indent}API Endpoint: ${apiUrl}\n`;
    summary += `${indent}Events Sent: Car Created → Loan Created → Loan Payment Submitted → Car Service Done\n`;
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
        }
    }
    
    if (data.metrics.http_req_failed) {
        const failed = data.metrics.http_req_failed;
        summary += `${indent}Error Rate: ${(failed.values.rate * 100).toFixed(2)}%\n`;
    }
    
    if (data.metrics.events_sent) {
        const sent = data.metrics.events_sent;
        summary += `${indent}Events Sent Successfully: ${sent.values.count}\n`;
    }
    
    if (data.metrics.errors) {
        const errors = data.metrics.errors;
        summary += `${indent}Errors: ${errors.values.rate.toFixed(4)} (${(errors.values.rate * 100).toFixed(2)}%)\n`;
    }
    
    summary += '\n';
    summary += `${indent}Next Steps:\n`;
    summary += `${indent}  1. Verify events in Aurora RDS database (business_events table)\n`;
    summary += `${indent}  2. Check entity tables (car_entities, loan_entities, loan_payment_entities, service_record_entities)\n`;
    summary += `${indent}  3. Check Lambda function logs in CloudWatch\n`;
    summary += `${indent}  4. Verify database schema: data/schema.sql\n`;
    summary += '\n';
    
    return summary;
}
