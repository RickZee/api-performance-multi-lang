/**
 * k6 Script to Send Batch Events to Java REST API
 * 
 * Sends 10 events of each type:
 * 1. Car Created (10 events)
 * 2. Loan Created (10 events)
 * 3. Loan Payment Submitted (10 events)
 * 
 * Total: 30 events
 * 
 * Flow: k6 → Java REST API → PostgreSQL → Confluent CDC → Confluent Cloud
 * 
 * Usage:
 *   k6 run --env HOST=producer-api-java-rest --env PORT=8081 send-batch-events.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';
import { randomString, randomIntBetween } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';

// Custom metrics
const errorRate = new Rate('errors');
const eventsSent = new Rate('events_sent');
const carEventsSent = new Rate('car_events_sent');
const loanEventsSent = new Rate('loan_events_sent');
const paymentEventsSent = new Rate('payment_events_sent');

// Test configuration - send 10 of each event type
const EVENTS_PER_TYPE = 10;
export const options = {
    vus: 1,
    iterations: EVENTS_PER_TYPE * 3, // 10 Car + 10 Loan + 10 Payment = 30 iterations
};

// Get API configuration from environment
const apiHost = __ENV.HOST || 'localhost';
const apiPort = __ENV.PORT || 8081;
const apiUrl = `http://${apiHost}:${apiPort}/api/v1/events`;

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
function generateCarCreatedEvent(carId = null) {
    const timestamp = generateTimestamp();
    const id = carId || `CAR-${new Date().toISOString().split('T')[0].replace(/-/g, '')}-${randomIntBetween(1, 9999)}`;
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
            entityId: id,
            updatedAttributes: {
            id: id,
            vin: `${randomString(17).toUpperCase()}`,
            make: ["Tesla", "Toyota", "Honda", "Ford", "BMW", "Mercedes", "Audi", "Lexus"][randomIntBetween(0, 7)],
            model: ["Model S", "Camry", "Accord", "F-150", "3 Series", "C-Class", "A4", "ES"][randomIntBetween(0, 7)],
            year: randomIntBetween(2020, 2025),
            color: ["Red", "Blue", "Black", "White", "Silver", "Gray"][randomIntBetween(0, 5)],
            mileage: randomIntBetween(0, 50000),
            lastServiceDate: timestamp,
            totalBalance: (randomIntBetween(0, 50000)).toFixed(2),
            lastLoanPaymentDate: timestamp,
            owner: `${randomString(8)} ${randomString(10)}`
            }
            }]
        }
    });
}

function generateLoanCreatedEvent(carId, loanId = null) {
    const timestamp = generateTimestamp();
    const id = loanId || `LOAN-${new Date().toISOString().split('T')[0].replace(/-/g, '')}-${randomIntBetween(1, 9999)}`;
    const uuid = generateUUID();
    const loanAmount = randomIntBetween(10000, 100000);
    const interestRate = (2.5 + Math.random() * 5).toFixed(2); // 2.5% - 7.5%
    const termMonths = [24, 36, 48, 60, 72][randomIntBetween(0, 4)];
    const monthlyPayment = (loanAmount * (1 + parseFloat(interestRate) / 100) / termMonths).toFixed(2);
    
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
            entityId: id,
            updatedAttributes: {
            id: id,
            carId: carId,
            financialInstitution: ["First National Bank", "Chase Bank", "Wells Fargo", "Bank of America", "Citibank"][randomIntBetween(0, 4)],
            balance: loanAmount.toFixed(2),
            lastPaidDate: timestamp,
            loanAmount: loanAmount.toFixed(2),
            interestRate: parseFloat(interestRate),
            termMonths: termMonths,
            startDate: timestamp,
            status: "active",
            monthlyPayment: monthlyPayment
            }
            }]
        }
    });
}

function generateLoanPaymentEvent(loanId, amount = null) {
    const timestamp = generateTimestamp();
    const paymentId = `PAYMENT-${new Date().toISOString().split('T')[0].replace(/-/g, '')}-${randomIntBetween(1, 9999)}`;
    const uuid = generateUUID();
    const paymentAmount = amount || (500 + Math.random() * 1500).toFixed(2); // $500-$2000
    
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
            amount: parseFloat(paymentAmount).toFixed(2),
            paymentDate: timestamp
            }
            }]
        }
    });
}

// Use setup function to generate linked IDs for each batch
export function setup() {
    const timestamp = new Date().toISOString().split('T')[0].replace(/-/g, '');
    const carIds = [];
    const loanIds = [];
    const monthlyPayments = [];
    
    // Generate 10 sets of linked IDs
    for (let i = 0; i < EVENTS_PER_TYPE; i++) {
        carIds.push(`CAR-${timestamp}-${i}-${randomIntBetween(1000, 9999)}`);
        loanIds.push(`LOAN-${timestamp}-${i}-${randomIntBetween(1000, 9999)}`);
        monthlyPayments.push((500 + Math.random() * 1500).toFixed(2));
    }
    
    return {
        carIds: carIds,
        loanIds: loanIds,
        monthlyPayments: monthlyPayments
    };
}

export default function (data) {
    const iteration = __ITER; // Current iteration (0-29)
    let payload;
    let eventType;
    let success;
    
    // Determine which event type based on iteration
    if (iteration < EVENTS_PER_TYPE) {
        // First 10 iterations: Car Created
        const carIndex = iteration;
        payload = generateCarCreatedEvent(data.carIds[carIndex]);
        eventType = "CarCreated";
    } else if (iteration < EVENTS_PER_TYPE * 2) {
        // Next 10 iterations: Loan Created
        const loanIndex = iteration - EVENTS_PER_TYPE;
        const carIndex = loanIndex; // Link to corresponding car
        payload = generateLoanCreatedEvent(data.carIds[carIndex], data.loanIds[loanIndex]);
        eventType = "LoanCreated";
    } else {
        // Last 10 iterations: Loan Payment Submitted
        const paymentIndex = iteration - (EVENTS_PER_TYPE * 2);
        const loanIndex = paymentIndex; // Link to corresponding loan
        payload = generateLoanPaymentEvent(data.loanIds[loanIndex], data.monthlyPayments[paymentIndex]);
        eventType = "LoanPaymentSubmitted";
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
    success = check(res, {
        'status is 200': (r) => r.status === 200,
        'response time < 5s': (r) => r.timings.duration < 5000,
        'response body contains success': (r) => {
            const body = r.body || '';
            return body.includes('successfully') || body.includes('processed') || body.includes('Event processed');
        },
    });
    
    errorRate.add(!success);
    eventsSent.add(success);
    
    // Track by event type
    if (eventType === "CarCreated") {
        carEventsSent.add(success);
    } else if (eventType === "LoanCreated") {
        loanEventsSent.add(success);
    } else if (eventType === "LoanPaymentSubmitted") {
        paymentEventsSent.add(success);
    }
    
    // Log progress every 5 events
    if (iteration % 5 === 0 || iteration === options.iterations - 1) {
        console.log(`Sent ${eventType} event (iteration ${iteration + 1}/${options.iterations})`);
    }
    
    // Small delay between events
    sleep(0.1);
}

export function handleSummary(data) {
    const totalRequests = data.metrics.http_reqs.values.count;
    const totalErrors = data.metrics.errors.values.count;
    const errorRate = totalRequests > 0 ? ((totalErrors / totalRequests) * 100).toFixed(2) : 0;
    
    const carSent = data.metrics.car_events_sent ? data.metrics.car_events_sent.values.count : 0;
    const loanSent = data.metrics.loan_events_sent ? data.metrics.loan_events_sent.values.count : 0;
    const paymentSent = data.metrics.payment_events_sent ? data.metrics.payment_events_sent.values.count : 0;
    
    const rate = data.metrics.http_req_duration?.values?.rate || 0;
    const avg = data.metrics.http_req_duration?.values?.avg || 0;
    const min = data.metrics.http_req_duration?.values?.min || 0;
    const max = data.metrics.http_req_duration?.values?.max || 0;
    const p95 = data.metrics.http_req_duration?.values?.['p(95)'] || 0;
    
    return {
        'stdout': `
========================================
k6 Batch Events Test Summary
========================================

API Endpoint: ${apiUrl}
Events Sent: 10 Car Created + 10 Loan Created + 10 Loan Payment Submitted
========================================

HTTP Requests:
  Total: ${totalRequests}
  Rate: ${rate.toFixed(2)} req/s
Response Time:
  Avg: ${avg.toFixed(2)}ms
  Min: ${min.toFixed(2)}ms
  Max: ${max.toFixed(2)}ms
  P95: ${p95.toFixed(2)}ms
Error Rate: ${errorRate}%
Errors: ${totalErrors}

Events by Type:
  Car Created: ${carSent}/10
  Loan Created: ${loanSent}/10
  Loan Payment Submitted: ${paymentSent}/10

Next Steps:
  1. Verify events in PostgreSQL database
  2. Check Confluent CDC connector status
  3. Verify events in Confluent Cloud input topics
  4. Check Flink jobs/SQL statements
  5. Verify events in Confluent Cloud output topics
`,
    };
}
