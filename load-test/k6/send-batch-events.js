/**
 * k6 Script to Send Batch Events to REST API (Regular or Lambda)
 * 
 * Sends configurable number of events of each type (always sends all 4 types):
 * 1. Car Created
 * 2. Loan Created
 * 3. Loan Payment Submitted
 * 4. Car Service Done
 * 
 * Flow: k6 → REST API → PostgreSQL → CDC → Confluent Cloud
 * 
 * Usage:
 *   # Send 5 events of each type (default, 4 types = 20 total, 1 VU per type = 4 VUs total)
 *   k6 run --env HOST=producer-api-java-rest --env PORT=8081 send-batch-events.js
 * 
 *   # Send 1000 events of each type with 10 VUs per type (4 types = 4000 total, 40 VUs total)
 *   k6 run --env HOST=producer-api-java-rest --env PORT=8081 --env EVENTS_PER_TYPE=1000 --env VUS_PER_EVENT_TYPE=10 send-batch-events.js
 * 
 *   # Lambda API with 1000 events per type, 20 VUs per type (4 types = 4000 total, 80 VUs total)
 *   k6 run --env API_URL=https://xxxxx.execute-api.us-east-1.amazonaws.com --env EVENTS_PER_TYPE=1000 --env VUS_PER_EVENT_TYPE=20 send-batch-events.js
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
const serviceEventsSent = new Rate('service_events_sent');

// Test configuration - configurable number of events per type via environment variable
// Default: 5 events per type (for quick testing)
// Set EVENTS_PER_TYPE environment variable to override (e.g., --env EVENTS_PER_TYPE=1000)
// Always sends all 4 event types: Car, Loan, Payment, Service
const EVENTS_PER_TYPE = parseInt(__ENV.EVENTS_PER_TYPE || '5', 10);
const NUM_EVENT_TYPES = 4; // Always 4: Car, Loan, Payment, Service

// Parallelism configuration - configurable VUs per event type
// Default: 1 VU per event type (sequential)
// Set VUS_PER_EVENT_TYPE to enable parallelism (e.g., --env VUS_PER_EVENT_TYPE=10)
// Total VUs = VUS_PER_EVENT_TYPE * NUM_EVENT_TYPES
// Each VU handles EVENTS_PER_TYPE / VUS_PER_EVENT_TYPE events of its assigned type
const VUS_PER_EVENT_TYPE = parseInt(__ENV.VUS_PER_EVENT_TYPE || '1', 10);
const TOTAL_VUS = VUS_PER_EVENT_TYPE * NUM_EVENT_TYPES;
const EVENTS_PER_VU = Math.ceil(EVENTS_PER_TYPE / VUS_PER_EVENT_TYPE);

export const options = {
    vus: TOTAL_VUS,
    iterations: EVENTS_PER_VU * TOTAL_VUS, // Total iterations: each VU runs EVENTS_PER_VU iterations
    thresholds: {
        // Abort if error rate exceeds 50% (half of requests failing)
        'http_req_failed': ['rate<0.5'],
    },
};

// Get API configuration from environment
// Support both regular REST API (HOST/PORT) and Lambda API (API_URL/LAMBDA_API_URL)
let apiUrl;
if (__ENV.API_URL || __ENV.LAMBDA_API_URL || __ENV.LAMBDA_PYTHON_REST_API_URL) {
    // Lambda API - use full URL
    const baseUrl = __ENV.API_URL || __ENV.LAMBDA_API_URL || __ENV.LAMBDA_PYTHON_REST_API_URL;
    const apiPath = __ENV.API_PATH || '/api/v1/events';
    apiUrl = baseUrl.includes('/api/v1/events') ? baseUrl : `${baseUrl.replace(/\/$/, '')}${apiPath}`;
} else {
    // Regular REST API - use HOST and PORT
    const apiHost = __ENV.HOST || 'localhost';
    const apiPort = __ENV.PORT || 8081;
    apiUrl = `http://${apiHost}:${apiPort}/api/v1/events`;
}

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

function generateCarServiceEvent(carId, serviceId = null) {
    const timestamp = generateTimestamp();
    const id = serviceId || `SERVICE-${new Date().toISOString().split('T')[0].replace(/-/g, '')}-${randomIntBetween(1, 9999)}`;
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

// Use setup function to generate linked IDs for each batch
export function setup() {
    const timestamp = new Date().toISOString().split('T')[0].replace(/-/g, '');
    const carIds = [];
    const loanIds = [];
    const monthlyPayments = [];
    const serviceIds = [];
    
    // Generate linked IDs for all events
    for (let i = 0; i < EVENTS_PER_TYPE; i++) {
        carIds.push(`CAR-${timestamp}-${i}-${randomIntBetween(1000, 9999)}`);
        loanIds.push(`LOAN-${timestamp}-${i}-${randomIntBetween(1000, 9999)}`);
        monthlyPayments.push((500 + Math.random() * 1500).toFixed(2));
        serviceIds.push(`SERVICE-${timestamp}-${i}-${randomIntBetween(1000, 9999)}`);
    }
    
    return {
        carIds: carIds,
        loanIds: loanIds,
        monthlyPayments: monthlyPayments,
        serviceIds: serviceIds
    };
}

export default function (data) {
    const vuId = __VU; // Virtual User ID (1 to TOTAL_VUS)
    const iteration = __ITER; // Current iteration for this VU (0 to EVENTS_PER_VU-1)
    let payload;
    let eventType;
    let success;
    let eventIndexInType; // Event index within the event type (0 to EVENTS_PER_TYPE-1)
    
    // Determine which event type this VU handles
    // VU assignment: VU 1-VUS_PER_EVENT_TYPE handle Car, 
    //                VU VUS_PER_EVENT_TYPE+1 to 2*VUS_PER_EVENT_TYPE handle Loan, etc.
    const eventTypeIndex = Math.floor((vuId - 1) / VUS_PER_EVENT_TYPE); // 0=Car, 1=Loan, 2=Payment, 3=Service
    const vuIndexInType = ((vuId - 1) % VUS_PER_EVENT_TYPE); // Position within event type (0 to VUS_PER_EVENT_TYPE-1)
    
    // Calculate which event index this VU should handle in this iteration
    // Events are split evenly across VUs: 
    //   VU 0 handles events 0, VUS_PER_EVENT_TYPE, 2*VUS_PER_EVENT_TYPE, etc.
    //   VU 1 handles events 1, VUS_PER_EVENT_TYPE+1, 2*VUS_PER_EVENT_TYPE+1, etc.
    //   This ensures even distribution and parallel processing
    eventIndexInType = vuIndexInType + (iteration * VUS_PER_EVENT_TYPE);
    
    // Ensure we don't exceed the number of events per type
    if (eventIndexInType >= EVENTS_PER_TYPE) {
        return; // This VU has finished its assigned events for this type
    }
    
    // Generate the appropriate event based on event type
    if (eventTypeIndex === 0) {
        // Car Created
        payload = generateCarCreatedEvent(data.carIds[eventIndexInType]);
        eventType = "CarCreated";
    } else if (eventTypeIndex === 1) {
        // Loan Created
        const carIndex = eventIndexInType; // Link to corresponding car
        payload = generateLoanCreatedEvent(data.carIds[carIndex], data.loanIds[eventIndexInType]);
        eventType = "LoanCreated";
    } else if (eventTypeIndex === 2) {
        // Loan Payment Submitted
        const loanIndex = eventIndexInType; // Link to corresponding loan
        payload = generateLoanPaymentEvent(data.loanIds[loanIndex], data.monthlyPayments[eventIndexInType]);
        eventType = "LoanPaymentSubmitted";
    } else {
        // Car Service Done
        const carIndex = eventIndexInType; // Link to corresponding car
        payload = generateCarServiceEvent(data.carIds[carIndex], data.serviceIds[eventIndexInType]);
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
    
    // Check response (use longer timeout for Lambda APIs)
    const isLambda = apiUrl.includes('execute-api') || apiUrl.includes('amazonaws.com');
    const timeout = isLambda ? 30000 : 5000; // 30s for Lambda, 5s for regular API
    
    success = check(res, {
        'status is 200': (r) => r.status === 200,
        [`response time < ${timeout}ms`]: (r) => r.timings.duration < timeout,
        'response body contains success': (r) => {
            const body = r.body || '';
            return body.includes('successfully') || body.includes('processed') || body.includes('Event processed') || r.status === 200;
        },
    });
    
    // Log errors immediately for visibility
    if (!success || res.status !== 200) {
        const errorMsg = res.status >= 400 ? `HTTP ${res.status}: ${res.body?.substring(0, 200) || 'No response body'}` : 'Request failed checks';
        console.error(`[ERROR] [VU ${vuId}] ${eventType} event failed (event ${eventIndexInType + 1}/${EVENTS_PER_TYPE}, iteration ${iteration + 1}/${options.iterations}): ${errorMsg}`);
        
        // Log first few errors in detail, then summarize
        if (iteration < 5) {
            console.error(`  Full response: ${JSON.stringify(res.body).substring(0, 500)}`);
        }
    }
    
    errorRate.add(!success);
    eventsSent.add(success);
    
    // Track by event type
    if (eventType === "CarCreated") {
        carEventsSent.add(success);
    } else if (eventType === "LoanCreated") {
        loanEventsSent.add(success);
    } else if (eventType === "LoanPaymentSubmitted") {
        paymentEventsSent.add(success);
    } else if (eventType === "CarServiceDone") {
        serviceEventsSent.add(success);
    }
    
    // Log progress periodically (every 10% or every 100 events, whichever is smaller)
    const logInterval = Math.max(1, Math.min(Math.floor(EVENTS_PER_VU / 10), 100));
    if (iteration % logInterval === 0 || iteration === options.iterations - 1) {
        console.log(`[VU ${vuId}] Sent ${eventType} event (${eventIndexInType + 1}/${EVENTS_PER_TYPE} for this type, iteration ${iteration + 1}/${options.iterations})`);
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
    const serviceSent = data.metrics.service_events_sent ? data.metrics.service_events_sent.values.count : 0;
    
    const rate = data.metrics.http_req_duration?.values?.rate || 0;
    const avg = data.metrics.http_req_duration?.values?.avg || 0;
    const min = data.metrics.http_req_duration?.values?.min || 0;
    const max = data.metrics.http_req_duration?.values?.max || 0;
    const p95 = data.metrics.http_req_duration?.values?.['p(95)'] || 0;
    
    // Build event summary string
    const eventsSummary = `${EVENTS_PER_TYPE} Car Created + ${EVENTS_PER_TYPE} Loan Created + ${EVENTS_PER_TYPE} Loan Payment Submitted + ${EVENTS_PER_TYPE} Car Service Done`;
    
    const eventsByType = `  Car Created: ${carSent}/${EVENTS_PER_TYPE}
    Loan Created: ${loanSent}/${EVENTS_PER_TYPE}
    Loan Payment Submitted: ${paymentSent}/${EVENTS_PER_TYPE}
    Car Service Done: ${serviceSent}/${EVENTS_PER_TYPE}`;
    
    return {
        'stdout': `
    ========================================
    k6 Batch Events Test Summary
    ========================================

    API Endpoint: ${apiUrl}
    Events Sent: ${eventsSummary}
    Total Events: ${EVENTS_PER_TYPE * NUM_EVENT_TYPES}
    Event Types: ${NUM_EVENT_TYPES}
    Parallelism: ${VUS_PER_EVENT_TYPE} VUs per event type (${TOTAL_VUS} total VUs)
    Events per VU: ${EVENTS_PER_VU} per event type
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
${eventsByType}

Next Steps:
  1. Verify events in PostgreSQL database
  2. Check Confluent CDC connector status
  3. Verify events in Confluent Cloud input topics
  4. Check Flink jobs/SQL statements
  5. Verify events in Confluent Cloud output topics
`,
    };
}
