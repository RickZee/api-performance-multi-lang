package com.loadtest.dsql;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fasterxml.jackson.databind.node.ArrayNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Instant;
import java.util.UUID;
import java.util.Random;
import java.util.function.Function;
import java.io.IOException;

/**
 * Generates test events for load testing.
 * Supports multiple event types and configurable payload sizes.
 */
public class EventGenerator {
    private static final Logger LOGGER = LoggerFactory.getLogger(EventGenerator.class);
    private static final ObjectMapper mapper = new ObjectMapper();
    private static final Random random = new Random();
    
    /**
     * Parse payload size from string.
     * Supports: '4k', '8k', '32k', '64k', '200k', '500k' or number in bytes.
     * 
     * @param sizeStr Size string (e.g., '4k', '8192', '32k')
     * @return Size in bytes or null if invalid
     */
    public static Integer parsePayloadSize(String sizeStr) {
        if (sizeStr == null || sizeStr.trim().isEmpty()) {
            return null;
        }
        
        String strVal = sizeStr.toLowerCase().trim();
        
        // Handle 'k' suffix (kilobytes)
        if (strVal.endsWith("k")) {
            try {
                int num = Integer.parseInt(strVal.substring(0, strVal.length() - 1));
                if (num > 0) {
                    return num * 1024;
                }
            } catch (NumberFormatException e) {
                // Invalid format
            }
        }
        
        // Handle plain number (bytes)
        try {
            int num = Integer.parseInt(strVal);
            if (num > 0) {
                return num;
            }
        } catch (NumberFormatException e) {
            // Invalid format
        }
        
        return null;
    }
    
    /**
     * Get target payload size from environment variable.
     * 
     * @return Size in bytes or null for default small payload
     */
    public static Integer getTargetPayloadSize() {
        String payloadSize = System.getenv("PAYLOAD_SIZE");
        return parsePayloadSize(payloadSize);
    }
    
    /**
     * Generate realistic description text of target length.
     * 
     * @param entityType Type of entity (Car, Loan, LoanPayment, ServiceRecord, etc.)
     * @param baseText Base description text to start with
     * @param targetChars Target number of characters
     * @return Description text of approximately targetChars length
     */
    private static String generateDescriptionText(String entityType, String baseText, int targetChars) {
        if (targetChars <= baseText.length()) {
            return baseText;
        }
        
        String[] descriptions = {
            "This vehicle has been well-maintained with regular service records.",
            "Account holder maintains active relationship with multiple services.",
            "Long-term customer with established account and verified identity.",
            "Account verified with complete documentation and background check.",
            "Policy includes additional benefits such as accident forgiveness and safe driver discounts.",
            "Funds transferred from linked checking account with instant processing.",
            "Service performed by certified technicians with OEM parts and quality assurance.",
            "Comprehensive inspection completed with detailed report and recommendations."
        };
        
        StringBuilder result = new StringBuilder(baseText);
        int needed = targetChars - baseText.length();
        
        while (result.length() < targetChars) {
            String desc = descriptions[random.nextInt(descriptions.length)];
            if (result.length() > 0) {
                result.append(" ");
            }
            result.append(desc);
            
            // Stop if we've exceeded target significantly
            if (result.length() > targetChars * 1.2) {
                break;
            }
        }
        
        // Trim to target if needed
        if (result.length() > targetChars) {
            return result.substring(0, targetChars);
        }
        
        return result.toString();
    }
    
    /**
     * Expand attributes to reach target size.
     * Adds realistic nested structures and padding based on entity type.
     * 
     * @param attributes Base attributes ObjectNode
     * @param targetSizeBytes Target size in bytes (null for default small payload)
     * @param entityId Entity ID to determine entity type
     * @return Expanded attributes ObjectNode
     */
    private static ObjectNode expandAttributesToSize(ObjectNode attributes, Integer targetSizeBytes, String entityId) {
        if (targetSizeBytes == null) {
            return attributes; // Return as-is for default small payload
        }
        
        // Create a copy to avoid modifying original
        ObjectNode expanded = attributes.deepCopy();
        
        String entityIdLower = entityId.toLowerCase();
        
        // Add nested structures based on entity type
        if (entityIdLower.contains("car")) {
            // Add car-specific nested data
            ObjectNode owner = mapper.createObjectNode();
            owner.put("id", "OWNER-" + randomString(8));
            owner.put("firstName", randomString(8));
            owner.put("lastName", randomString(10));
            owner.put("email", randomString(10) + "@example.com");
            owner.put("phone", "+1-555-" + randomString(7));
            ObjectNode address = mapper.createObjectNode();
            address.put("street", random.nextInt(9999) + " " + randomString(10) + " Street");
            address.put("city", randomString(12));
            address.put("state", randomString(2).toUpperCase());
            address.put("zipCode", randomString(5));
            address.put("country", "USA");
            owner.set("address", address);
            owner.put("description", "Information about owner. Account holder maintains active relationship with multiple services.");
            expanded.set("owner", owner);
            
            ObjectNode insurance = mapper.createObjectNode();
            insurance.put("provider", randomString(12));
            insurance.put("policyNumber", "POL-" + randomString(10));
            insurance.put("expiryDate", Instant.now().toString());
            insurance.put("coverageType", "Full Coverage");
            insurance.put("premiumAmount", random.nextInt(1500) + 500);
            insurance.put("deductible", random.nextInt(750) + 250);
            insurance.put("description", "Information about insurance. Coverage extends to all drivers with full protection and peace of mind.");
            expanded.set("insurance", insurance);
            
            ObjectNode maintenance = mapper.createObjectNode();
            maintenance.put("lastServiceDate", Instant.now().toString());
            maintenance.put("nextServiceDue", Instant.now().toString());
            maintenance.put("mileage", random.nextInt(100000));
            maintenance.put("oilChangeInterval", random.nextInt(10000) + 5000);
            maintenance.put("tireRotationInterval", random.nextInt(5000) + 5000);
            maintenance.put("warrantyCoverage", "Active");
            maintenance.put("warrantyExpiryDate", Instant.now().toString());
            maintenance.put("description", "Information about maintenance. Preventive maintenance performed to ensure optimal vehicle performance and reliability.");
            expanded.set("maintenance", maintenance);
            
            // Add features array
            int featureCount = Math.max(5, targetSizeBytes / 2000);
            ArrayNode features = mapper.createArrayNode();
            for (int i = 0; i < featureCount; i++) {
                features.add(randomString(15));
            }
            expanded.set("features", features);
            
            // Add service history array
            int historyCount = Math.max(2, targetSizeBytes / 3000);
            ArrayNode serviceHistory = mapper.createArrayNode();
            for (int i = 0; i < historyCount; i++) {
                ObjectNode history = mapper.createObjectNode();
                history.put("serviceId", "SVC-" + randomString(8));
                history.put("serviceDate", Instant.now().toString());
                history.put("serviceType", randomString(10));
                history.put("mileage", random.nextInt(100000));
                history.put("cost", random.nextInt(900) + 100);
                history.put("description", randomString(50));
                history.put("technician", randomString(15));
                serviceHistory.add(history);
            }
            expanded.set("serviceHistory", serviceHistory);
            
        } else if (entityIdLower.contains("loan") || entityIdLower.contains("payment")) {
            // Add loan-specific nested data
            ObjectNode financialInstitution = mapper.createObjectNode();
            financialInstitution.put("name", randomString(15));
            financialInstitution.put("routingNumber", randomString(9));
            financialInstitution.put("accountNumber", randomString(12));
            ObjectNode contact = mapper.createObjectNode();
            contact.put("phone", "+1-555-" + randomString(7));
            contact.put("email", randomString(10) + "@bank.com");
            financialInstitution.set("contact", contact);
            expanded.set("financialInstitution", financialInstitution);
            
            ArrayNode paymentHistory = mapper.createArrayNode();
            int historyCount = Math.max(3, targetSizeBytes / 2000);
            for (int i = 0; i < historyCount; i++) {
                ObjectNode payment = mapper.createObjectNode();
                payment.put("paymentId", "PAY-" + randomString(8));
                payment.put("amount", String.format("%.2f", random.nextDouble() * 1900 + 100));
                payment.put("date", Instant.now().toString());
                payment.put("status", "completed");
                payment.put("transactionId", randomString(16));
                paymentHistory.add(payment);
            }
            expanded.set("paymentHistory", paymentHistory);
            
            ObjectNode terms = mapper.createObjectNode();
            terms.put("interestRate", String.format("%.2f", random.nextDouble() * 10));
            terms.put("termMonths", random.nextInt(73) + 12);
            terms.put("monthlyPayment", String.format("%.2f", random.nextDouble() * 600 + 200));
            terms.put("startDate", Instant.now().toString());
            terms.put("endDate", Instant.now().toString());
            expanded.set("terms", terms);
            
        } else if (entityIdLower.contains("service")) {
            // Add service-specific nested data
            ObjectNode dealer = mapper.createObjectNode();
            dealer.put("id", "DEALER-" + randomString(8));
            dealer.put("name", randomString(20));
            ObjectNode dealerAddress = mapper.createObjectNode();
            dealerAddress.put("street", random.nextInt(9999) + " " + randomString(10) + " Avenue");
            dealerAddress.put("city", randomString(12));
            dealerAddress.put("state", randomString(2).toUpperCase());
            dealerAddress.put("zipCode", randomString(5));
            dealer.set("address", dealerAddress);
            dealer.put("phone", "+1-555-" + randomString(7));
            dealer.put("email", randomString(10) + "@dealer.com");
            expanded.set("dealer", dealer);
            
            ArrayNode parts = mapper.createArrayNode();
            int partsCount = Math.max(2, targetSizeBytes / 1500);
            for (int i = 0; i < partsCount; i++) {
                ObjectNode part = mapper.createObjectNode();
                part.put("partId", "PART-" + randomString(8));
                part.put("name", randomString(20));
                part.put("quantity", random.nextInt(5) + 1);
                part.put("cost", String.format("%.2f", random.nextDouble() * 190 + 10));
                part.put("manufacturer", randomString(15));
                parts.add(part);
            }
            expanded.set("parts", parts);
            
            ObjectNode technician = mapper.createObjectNode();
            technician.put("id", "TECH-" + randomString(8));
            technician.put("name", randomString(15));
            technician.put("certification", randomString(10));
            technician.put("experience", random.nextInt(20) + 1);
            expanded.set("technician", technician);
        }
        
        // Add metadata
        ObjectNode metadata = mapper.createObjectNode();
        metadata.put("createdAt", Instant.now().toString());
        metadata.put("updatedAt", Instant.now().toString());
        metadata.put("createdBy", randomString(10));
        metadata.put("source", randomString(15));
        metadata.put("dataVersion", "1.0");
        metadata.set("tags", mapper.createArrayNode());
        expanded.set("metadata", metadata);
        
        // Calculate current size and expand description fields to reach target size
        try {
            String currentJson = mapper.writeValueAsString(expanded);
            int currentSize = currentJson.getBytes("UTF-8").length;
            
            if (currentSize < targetSizeBytes) {
                int sizeNeeded = targetSizeBytes - currentSize;
                
                // Determine entity type from entity_id
                String entityType = "Car";
                if (entityIdLower.contains("loan") || entityIdLower.contains("payment")) {
                    entityType = entityIdLower.contains("payment") ? "LoanPayment" : "Loan";
                } else if (entityIdLower.contains("service")) {
                    entityType = "ServiceRecord";
                }
                
                // Estimate: each character in description adds roughly 1 byte in JSON
                // Account for JSON structure overhead (quotes, colons, etc.) - roughly 20% overhead
                int descriptionCharsNeeded = (int)(sizeNeeded * 0.8);
                
                // Add/expand description to main entity
                String baseDescription = expanded.has("description") ? expanded.get("description").asText() : "";
                if (baseDescription.isEmpty()) {
                    if ("Car".equals(entityType)) {
                        String make = expanded.has("make") ? expanded.get("make").asText() : "vehicle";
                        String model = expanded.has("model") ? expanded.get("model").asText() : "";
                        baseDescription = "This " + make + " " + model + " is in excellent condition.";
                    } else if ("Loan".equals(entityType)) {
                        baseDescription = "This loan has been established with favorable terms and conditions.";
                    } else if ("LoanPayment".equals(entityType)) {
                        baseDescription = "This payment has been processed successfully through our secure payment system.";
                    } else if ("ServiceRecord".equals(entityType)) {
                        baseDescription = "Service performed by certified technicians.";
                    }
                }
                
                expanded.put("description", generateDescriptionText(entityType, baseDescription, descriptionCharsNeeded));
                
                // Final check - if still too small, expand main description further
                String finalJson = mapper.writeValueAsString(expanded);
                int finalSize = finalJson.getBytes("UTF-8").length;
                
                if (finalSize < targetSizeBytes) {
                    int additionalNeeded = targetSizeBytes - finalSize;
                    int additionalChars = (int)(additionalNeeded * 0.8);
                    String currentDesc = expanded.has("description") ? expanded.get("description").asText() : "";
                    expanded.put("description", generateDescriptionText(entityType, currentDesc, currentDesc.length() + additionalChars));
                }
            }
        } catch (Exception e) {
            LOGGER.warn("Error expanding attributes to size: {}", e.getMessage());
        }
        
        return expanded;
    }
    
    /**
     * Get event generator function based on event type.
     * 
     * @param eventType Event type: "CarCreated", "LoanCreated", "LoanPaymentSubmitted", "CarServiceDone", or "random"
     * @return Function that generates the event
     */
    public static Function<String, ObjectNode> getEventGenerator(String eventType) {
        if (eventType == null) {
            eventType = "CarCreated";
        }
        
        switch (eventType) {
            case "LoanCreated":
                return (carId) -> generateLoanCreatedEvent(carId, null, null);
            case "LoanPaymentSubmitted":
                return (loanId) -> generateLoanPaymentEvent(loanId, null, null);
            case "CarServiceDone":
                return (carId) -> generateCarServiceEvent(carId, null, null);
            case "random":
                String[] types = {"CarCreated", "LoanCreated", "LoanPaymentSubmitted", "CarServiceDone"};
                String randomType = types[random.nextInt(types.length)];
                return getEventGenerator(randomType);
            case "CarCreated":
            default:
                return (carId) -> generateCarCreatedEvent(null, null);
        }
    }
    
    /**
     * Generate Car Created event.
     * 
     * @param carId Optional car ID (generated if not provided)
     * @param payloadSize Optional target payload size in bytes
     * @return Event ObjectNode
     */
    public static ObjectNode generateCarCreatedEvent(String carId, Integer payloadSize) {
        if (payloadSize == null) {
            payloadSize = getTargetPayloadSize();
        }
        
        String now = Instant.now().toString();
        String dateStr = now.substring(0, 10).replace("-", "");
        String idVal = carId != null ? carId : "CAR-" + dateStr + "-" + (random.nextInt(9999) + 1);
        String eventUuid = UUID.randomUUID().toString();
        
        String[] makes = {"Tesla", "Toyota", "Honda", "Ford", "BMW", "Mercedes", "Audi", "Lexus"};
        String[] models = {"Model S", "Camry", "Accord", "F-150", "3 Series", "C-Class", "A4", "ES"};
        String[] colors = {"Red", "Blue", "Black", "White", "Silver", "Gray"};
        
        // Base attributes
        ObjectNode baseAttributes = mapper.createObjectNode();
        baseAttributes.put("id", idVal);
        baseAttributes.put("vin", randomString(17).toUpperCase());
        baseAttributes.put("make", makes[random.nextInt(makes.length)]);
        baseAttributes.put("model", models[random.nextInt(models.length)]);
        baseAttributes.put("year", random.nextInt(6) + 2020);
        baseAttributes.put("color", colors[random.nextInt(colors.length)]);
        baseAttributes.put("mileage", random.nextInt(50001));
        baseAttributes.put("lastServiceDate", now);
        baseAttributes.put("totalBalance", String.format("%.2f", (double)(random.nextInt(50001))));
        baseAttributes.put("lastLoanPaymentDate", now);
        baseAttributes.put("owner", randomString(8) + " " + randomString(10));
        
        // Expand attributes to target size if specified
        ObjectNode expandedAttributes = expandAttributesToSize(baseAttributes, payloadSize, idVal);
        
        // Build event
        ObjectNode event = mapper.createObjectNode();
        ObjectNode eventHeader = mapper.createObjectNode();
        eventHeader.put("uuid", eventUuid);
        eventHeader.put("eventName", "Car Created");
        eventHeader.put("eventType", "CarCreated");
        eventHeader.put("createdDate", now);
        eventHeader.put("savedDate", now);
        event.set("eventHeader", eventHeader);
        
        ArrayNode entities = mapper.createArrayNode();
        ObjectNode entity = mapper.createObjectNode();
        ObjectNode entityHeader = mapper.createObjectNode();
        entityHeader.put("entityId", idVal);
        entityHeader.put("entityType", "Car");
        entityHeader.put("createdAt", now);
        entityHeader.put("updatedAt", now);
        entity.set("entityHeader", entityHeader);
        
        // Copy all expanded attributes to entity
        expandedAttributes.fields().forEachRemaining(entry -> entity.set(entry.getKey(), entry.getValue()));
        
        entities.add(entity);
        event.set("entities", entities);
        
        // Final size check
        if (payloadSize != null) {
            try {
                String eventJson = mapper.writeValueAsString(event);
                int currentSize = eventJson.getBytes("UTF-8").length;
                if (currentSize < payloadSize) {
                    String attributesJson = mapper.writeValueAsString(expandedAttributes);
                    int attributesSize = attributesJson.getBytes("UTF-8").length;
                    int attributesTarget = payloadSize - (currentSize - attributesSize);
                    ObjectNode finalAttributes = expandAttributesToSize(baseAttributes, attributesTarget, idVal);
                    finalAttributes.fields().forEachRemaining(entry -> entity.set(entry.getKey(), entry.getValue()));
                }
            } catch (Exception e) {
                LOGGER.warn("Error in final size check: {}", e.getMessage());
            }
        }
        
        return event;
    }
    
    /**
     * Generate Loan Created event.
     * 
     * @param carId Car ID for the loan
     * @param loanId Optional loan ID (generated if not provided)
     * @param payloadSize Optional target payload size in bytes
     * @return Event ObjectNode
     */
    public static ObjectNode generateLoanCreatedEvent(String carId, String loanId, Integer payloadSize) {
        if (payloadSize == null) {
            payloadSize = getTargetPayloadSize();
        }
        
        String now = Instant.now().toString();
        String dateStr = now.substring(0, 10).replace("-", "");
        String idVal = loanId != null ? loanId : "LOAN-" + dateStr + "-" + (random.nextInt(9999) + 1);
        String eventUuid = UUID.randomUUID().toString();
        
        int loanAmount = random.nextInt(90001) + 10000;
        double interestRate = 0.025 + random.nextDouble() * 0.05; // 2.5% - 7.5%
        int[] termMonths = {24, 36, 48, 60, 72};
        int termMonthsVal = termMonths[random.nextInt(termMonths.length)];
        double monthlyPayment = (loanAmount * (1 + interestRate)) / termMonthsVal;
        
        String[] institutions = {"First National Bank", "Chase Bank", "Wells Fargo", "Bank of America", "Citibank"};
        
        // Base attributes
        ObjectNode baseAttributes = mapper.createObjectNode();
        baseAttributes.put("id", idVal);
        baseAttributes.put("carId", carId);
        baseAttributes.put("financialInstitution", institutions[random.nextInt(institutions.length)]);
        baseAttributes.put("balance", String.format("%.2f", (double)loanAmount));
        baseAttributes.put("lastPaidDate", now);
        baseAttributes.put("loanAmount", String.format("%.2f", (double)loanAmount));
        baseAttributes.put("interestRate", interestRate);
        baseAttributes.put("termMonths", termMonthsVal);
        baseAttributes.put("startDate", now);
        baseAttributes.put("status", "active");
        baseAttributes.put("monthlyPayment", String.format("%.2f", monthlyPayment));
        
        // Expand attributes to target size if specified
        ObjectNode expandedAttributes = expandAttributesToSize(baseAttributes, payloadSize, idVal);
        
        // Build event
        ObjectNode event = mapper.createObjectNode();
        ObjectNode eventHeader = mapper.createObjectNode();
        eventHeader.put("uuid", eventUuid);
        eventHeader.put("eventName", "Loan Created");
        eventHeader.put("eventType", "LoanCreated");
        eventHeader.put("createdDate", now);
        eventHeader.put("savedDate", now);
        event.set("eventHeader", eventHeader);
        
        ArrayNode entities = mapper.createArrayNode();
        ObjectNode entity = mapper.createObjectNode();
        ObjectNode entityHeader = mapper.createObjectNode();
        entityHeader.put("entityId", idVal);
        entityHeader.put("entityType", "Loan");
        entityHeader.put("createdAt", now);
        entityHeader.put("updatedAt", now);
        entity.set("entityHeader", entityHeader);
        
        // Copy all expanded attributes to entity
        expandedAttributes.fields().forEachRemaining(entry -> entity.set(entry.getKey(), entry.getValue()));
        
        entities.add(entity);
        event.set("entities", entities);
        
        // Final size check
        if (payloadSize != null) {
            try {
                String eventJson = mapper.writeValueAsString(event);
                int currentSize = eventJson.getBytes("UTF-8").length;
                if (currentSize < payloadSize) {
                    String attributesJson = mapper.writeValueAsString(expandedAttributes);
                    int attributesSize = attributesJson.getBytes("UTF-8").length;
                    int attributesTarget = payloadSize - (currentSize - attributesSize);
                    ObjectNode finalAttributes = expandAttributesToSize(baseAttributes, attributesTarget, idVal);
                    finalAttributes.fields().forEachRemaining(entry -> entity.set(entry.getKey(), entry.getValue()));
                }
            } catch (Exception e) {
                LOGGER.warn("Error in final size check: {}", e.getMessage());
            }
        }
        
        return event;
    }
    
    /**
     * Generate Loan Payment Submitted event.
     * 
     * @param loanId Loan ID for the payment
     * @param amount Optional payment amount (generated if not provided)
     * @param payloadSize Optional target payload size in bytes
     * @return Event ObjectNode
     */
    public static ObjectNode generateLoanPaymentEvent(String loanId, Double amount, Integer payloadSize) {
        if (payloadSize == null) {
            payloadSize = getTargetPayloadSize();
        }
        
        String now = Instant.now().toString();
        String dateStr = now.substring(0, 10).replace("-", "");
        String paymentId = "PAYMENT-" + dateStr + "-" + (random.nextInt(9999) + 1);
        String eventUuid = UUID.randomUUID().toString();
        double paymentAmount = amount != null ? amount : 500 + random.nextDouble() * 1500;
        
        // Base attributes
        ObjectNode baseAttributes = mapper.createObjectNode();
        baseAttributes.put("id", paymentId);
        baseAttributes.put("loanId", loanId);
        baseAttributes.put("amount", String.format("%.2f", paymentAmount));
        baseAttributes.put("paymentDate", now);
        
        // Expand attributes to target size if specified
        ObjectNode expandedAttributes = expandAttributesToSize(baseAttributes, payloadSize, paymentId);
        
        // Build event
        ObjectNode event = mapper.createObjectNode();
        ObjectNode eventHeader = mapper.createObjectNode();
        eventHeader.put("uuid", eventUuid);
        eventHeader.put("eventName", "Loan Payment Submitted");
        eventHeader.put("eventType", "LoanPaymentSubmitted");
        eventHeader.put("createdDate", now);
        eventHeader.put("savedDate", now);
        event.set("eventHeader", eventHeader);
        
        ArrayNode entities = mapper.createArrayNode();
        ObjectNode entity = mapper.createObjectNode();
        ObjectNode entityHeader = mapper.createObjectNode();
        entityHeader.put("entityId", paymentId);
        entityHeader.put("entityType", "LoanPayment");
        entityHeader.put("createdAt", now);
        entityHeader.put("updatedAt", now);
        entity.set("entityHeader", entityHeader);
        
        // Copy all expanded attributes to entity
        expandedAttributes.fields().forEachRemaining(entry -> entity.set(entry.getKey(), entry.getValue()));
        
        entities.add(entity);
        event.set("entities", entities);
        
        // Final size check
        if (payloadSize != null) {
            try {
                String eventJson = mapper.writeValueAsString(event);
                int currentSize = eventJson.getBytes("UTF-8").length;
                if (currentSize < payloadSize) {
                    String attributesJson = mapper.writeValueAsString(expandedAttributes);
                    int attributesSize = attributesJson.getBytes("UTF-8").length;
                    int attributesTarget = payloadSize - (currentSize - attributesSize);
                    ObjectNode finalAttributes = expandAttributesToSize(baseAttributes, attributesTarget, paymentId);
                    finalAttributes.fields().forEachRemaining(entry -> entity.set(entry.getKey(), entry.getValue()));
                }
            } catch (Exception e) {
                LOGGER.warn("Error in final size check: {}", e.getMessage());
            }
        }
        
        return event;
    }
    
    /**
     * Generate Car Service Done event.
     * 
     * @param carId Car ID for the service
     * @param serviceId Optional service ID (generated if not provided)
     * @param payloadSize Optional target payload size in bytes
     * @return Event ObjectNode
     */
    public static ObjectNode generateCarServiceEvent(String carId, String serviceId, Integer payloadSize) {
        if (payloadSize == null) {
            payloadSize = getTargetPayloadSize();
        }
        
        String now = Instant.now().toString();
        String dateStr = now.substring(0, 10).replace("-", "");
        String idVal = serviceId != null ? serviceId : "SERVICE-" + dateStr + "-" + (random.nextInt(9999) + 1);
        String eventUuid = UUID.randomUUID().toString();
        double amountPaid = 100 + random.nextDouble() * 1000;
        int mileageAtService = random.nextInt(99000) + 1000;
        
        String[] dealers = {
            "Tesla Service Center - San Francisco",
            "Toyota Service Center - Los Angeles",
            "Honda Service Center - New York",
            "Ford Service Center - Chicago",
            "BMW Service Center - Miami"
        };
        String dealerId = "DEALER-" + (random.nextInt(999) + 1);
        String dealerName = dealers[random.nextInt(dealers.length)];
        
        String[] descriptions = {
            "Regular maintenance service including tire rotation, brake inspection, and fluid top-up",
            "Oil change and filter replacement",
            "Brake pad replacement and brake fluid flush",
            "Transmission service and fluid change",
            "Battery replacement and electrical system check"
        };
        String description = descriptions[random.nextInt(descriptions.length)];
        
        // Base attributes
        ObjectNode baseAttributes = mapper.createObjectNode();
        baseAttributes.put("id", idVal);
        baseAttributes.put("carId", carId);
        baseAttributes.put("serviceDate", now);
        baseAttributes.put("amountPaid", String.format("%.2f", amountPaid));
        baseAttributes.put("dealerId", dealerId);
        baseAttributes.put("dealerName", dealerName);
        baseAttributes.put("mileageAtService", mileageAtService);
        baseAttributes.put("description", description);
        
        // Expand attributes to target size if specified
        ObjectNode expandedAttributes = expandAttributesToSize(baseAttributes, payloadSize, idVal);
        
        // Build event
        ObjectNode event = mapper.createObjectNode();
        ObjectNode eventHeader = mapper.createObjectNode();
        eventHeader.put("uuid", eventUuid);
        eventHeader.put("eventName", "Car Service Done");
        eventHeader.put("eventType", "CarServiceDone");
        eventHeader.put("createdDate", now);
        eventHeader.put("savedDate", now);
        event.set("eventHeader", eventHeader);
        
        ArrayNode entities = mapper.createArrayNode();
        ObjectNode entity = mapper.createObjectNode();
        ObjectNode entityHeader = mapper.createObjectNode();
        entityHeader.put("entityId", idVal);
        entityHeader.put("entityType", "ServiceRecord");
        entityHeader.put("createdAt", now);
        entityHeader.put("updatedAt", now);
        entity.set("entityHeader", entityHeader);
        
        // Copy all expanded attributes to entity
        expandedAttributes.fields().forEachRemaining(entry -> entity.set(entry.getKey(), entry.getValue()));
        
        entities.add(entity);
        event.set("entities", entities);
        
        // Final size check
        if (payloadSize != null) {
            try {
                String eventJson = mapper.writeValueAsString(event);
                int currentSize = eventJson.getBytes("UTF-8").length;
                if (currentSize < payloadSize) {
                    String attributesJson = mapper.writeValueAsString(expandedAttributes);
                    int attributesSize = attributesJson.getBytes("UTF-8").length;
                    int attributesTarget = payloadSize - (currentSize - attributesSize);
                    ObjectNode finalAttributes = expandAttributesToSize(baseAttributes, attributesTarget, idVal);
                    finalAttributes.fields().forEachRemaining(entry -> entity.set(entry.getKey(), entry.getValue()));
                }
            } catch (Exception e) {
                LOGGER.warn("Error in final size check: {}", e.getMessage());
            }
        }
        
        return event;
    }
    
    private static String randomString(int length) {
        String chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < length; i++) {
            sb.append(chars.charAt(random.nextInt(chars.length())));
        }
        return sb.toString();
    }
    
    private static String generateVIN() {
        String chars = "ABCDEFGHJKLMNPRSTUVWXYZ0123456789";
        StringBuilder vin = new StringBuilder();
        for (int i = 0; i < 17; i++) {
            vin.append(chars.charAt(random.nextInt(chars.length())));
        }
        return vin.toString();
    }
    
    private static String getRandomMake() {
        String[] makes = {"Toyota", "Honda", "Ford", "Chevrolet", "BMW", "Mercedes-Benz", "Audi", "Volkswagen"};
        return makes[random.nextInt(makes.length)];
    }
    
    private static String getRandomModel() {
        String[] models = {"Camry", "Accord", "F-150", "Silverado", "X5", "C-Class", "A4", "Jetta"};
        return models[random.nextInt(models.length)];
    }
    
    private static String getRandomColor() {
        String[] colors = {"Black", "White", "Silver", "Red", "Blue", "Gray", "Green"};
        return colors[random.nextInt(colors.length)];
    }
}
