/**
 * Shared event generation utilities for k6 tests
 * Import this module in k6 scripts: import { generateCarCreatedEvent, ... } from './shared/event-generators.js';
 */

import { randomString, randomIntBetween } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';

/**
 * Generate a UUID v4
 */
export function generateUUID() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
        const r = Math.random() * 16 | 0;
        const v = c === 'x' ? r : (r & 0x3 | 0x8);
        return v.toString(16);
    });
}

/**
 * Generate ISO 8601 timestamp
 */
export function generateTimestamp() {
    return new Date().toISOString();
}

/**
 * Generate Car Created event
 */
export function generateCarCreatedEvent(carId = null) {
    const timestamp = generateTimestamp();
    const id = carId || `CAR-${new Date().toISOString().split('T')[0].replace(/-/g, '')}-${randomIntBetween(1, 999)}`;
    const uuid = generateUUID();
    
    return JSON.stringify({
        eventHeader: {
            uuid: uuid,
            eventName: "Car Created",
            eventType: "CarCreated",
            createdDate: timestamp,
            savedDate: timestamp
        },
        entities: [{
            entityHeader: {
                entityId: id,
                entityType: "Car",
                createdAt: timestamp,
                updatedAt: timestamp
            },
            id: id,
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
        }]
    });
}

/**
 * Generate Loan Created event
 */
export function generateLoanCreatedEvent(carId, loanId = null) {
    const timestamp = generateTimestamp();
    const id = loanId || `LOAN-${new Date().toISOString().split('T')[0].replace(/-/g, '')}-${randomIntBetween(1, 999)}`;
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
        entities: [{
            entityHeader: {
                entityId: id,
                entityType: "Loan",
                createdAt: timestamp,
                updatedAt: timestamp
            },
            id: id,
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
        }]
    });
}

/**
 * Generate Loan Payment Submitted event
 */
export function generateLoanPaymentEvent(loanId, amount = null) {
    const timestamp = generateTimestamp();
    const paymentId = `PAYMENT-${new Date().toISOString().split('T')[0].replace(/-/g, '')}-${randomIntBetween(1, 999)}`;
    const uuid = generateUUID();
    const paymentAmount = amount || (500 + Math.random() * 1500).toFixed(2);
    
    return JSON.stringify({
        eventHeader: {
            uuid: uuid,
            eventName: "Loan Payment Submitted",
            eventType: "LoanPaymentSubmitted",
            createdDate: timestamp,
            savedDate: timestamp
        },
        entities: [{
            entityHeader: {
                entityId: paymentId,
                entityType: "LoanPayment",
                createdAt: timestamp,
                updatedAt: timestamp
            },
            id: paymentId,
            loanId: loanId,
            amount: parseFloat(paymentAmount).toFixed(2),
            paymentDate: timestamp
        }]
    });
}

/**
 * Generate Car Service Done event
 */
export function generateCarServiceDoneEvent(carId, serviceId = null) {
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
        entities: [{
            entityHeader: {
                entityId: id,
                entityType: "ServiceRecord",
                createdAt: timestamp,
                updatedAt: timestamp
            },
            id: id,
            carId: carId,
            serviceDate: timestamp,
            amountPaid: parseFloat(amountPaid).toFixed(2),
            dealerId: dealerId,
            dealerName: dealerName,
            mileageAtService: mileageAtService,
            description: description
        }]
    });
}

/**
 * Generate linked event set (Car -> Loan -> Payment -> Service)
 */
export function generateLinkedEventSet() {
    const timestamp = new Date().toISOString().split('T')[0].replace(/-/g, '');
    const carId = `CAR-${timestamp}-${Math.floor(Math.random() * 1000)}`;
    const loanId = `LOAN-${timestamp}-${Math.floor(Math.random() * 1000)}`;
    const serviceId = `SERVICE-${timestamp}-${Math.floor(Math.random() * 1000)}`;
    const monthlyPayment = (500 + Math.random() * 1500).toFixed(2);
    
    return {
        carId: carId,
        loanId: loanId,
        serviceId: serviceId,
        monthlyPayment: monthlyPayment,
        carEvent: JSON.parse(generateCarCreatedEvent(carId)),
        loanEvent: JSON.parse(generateLoanCreatedEvent(carId, loanId)),
        paymentEvent: JSON.parse(generateLoanPaymentEvent(loanId, monthlyPayment)),
        serviceEvent: JSON.parse(generateCarServiceDoneEvent(carId, serviceId))
    };
}

