package com.bulk.ingestion.generator;

import com.bulk.ingestion.model.Event;
import com.bulk.ingestion.model.EventBody;
import com.bulk.ingestion.model.EventHeader;
import com.bulk.ingestion.model.EntityUpdate;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.time.OffsetDateTime;
import java.util.*;

/**
 * Test data generator for creating sample events
 */
@Component
public class TestDataGenerator {
    
    private static final Logger logger = LoggerFactory.getLogger(TestDataGenerator.class);
    
    private final ObjectMapper objectMapper;
    private final Random random;
    
    // Sample data for generating realistic events
    private static final String[] CAR_MAKES = {"Honda", "Toyota", "Ford", "BMW", "Mercedes", "Audi", "Nissan", "Hyundai"};
    private static final String[] CAR_MODELS = {"Civic", "Camry", "Focus", "X3", "C-Class", "A4", "Altima", "Elantra"};
    private static final String[] COLORS = {"Blue", "Red", "White", "Black", "Silver", "Gray", "Green", "Yellow"};
    private static final String[] FINANCIAL_INSTITUTIONS = {"ABC Bank", "XYZ Credit Union", "First National", "Community Bank", "Metro Financial"};
    private static final String[] EVENT_TYPES = {"LoanPaymentSubmitted", "CarServiceDone", "LoanCreated", "CarRegistered"};
    
    @Autowired
    public TestDataGenerator(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
        this.random = new Random();
    }
    
    /**
     * Generate a specified number of events
     * @param count the number of events to generate
     * @return list of generated events
     */
    public List<Event> generateEvents(int count) {
        logger.info("Generating {} test events", count);
        
        List<Event> events = new ArrayList<>();
        for (int i = 0; i < count; i++) {
            events.add(generateEvent(i));
        }
        
        logger.info("Generated {} test events", events.size());
        return events;
    }
    
    /**
     * Generate events and save to JSONL file
     * @param count the number of events to generate
     * @param outputFile the output file path
     * @throws IOException if file writing fails
     */
    public void generateEventsToFile(int count, String outputFile) throws IOException {
        logger.info("Generating {} test events to file: {}", count, outputFile);
        
        File file = new File(outputFile);
        file.getParentFile().mkdirs();
        
        try (FileWriter writer = new FileWriter(file)) {
            for (int i = 0; i < count; i++) {
                Event event = generateEvent(i);
                String json = objectMapper.writeValueAsString(event);
                writer.write(json + "\n");
                
                if ((i + 1) % 1000 == 0) {
                    logger.info("Generated {} events", i + 1);
                }
            }
        }
        
        logger.info("Successfully generated {} events to file: {}", count, outputFile);
    }
    
    /**
     * Generate a single event
     * @param index the event index
     * @return the generated event
     */
    private Event generateEvent(int index) {
        String eventType = EVENT_TYPES[random.nextInt(EVENT_TYPES.length)];
        String uuid = UUID.randomUUID().toString();
        OffsetDateTime now = OffsetDateTime.now();
        
        EventHeader header = new EventHeader(
            uuid,
            eventType,
            now.minusSeconds(random.nextInt(3600)), // Created up to 1 hour ago
            now,
            eventType
        );
        
        EventBody body = new EventBody();
        List<EntityUpdate> entities = new ArrayList<>();
        
        switch (eventType) {
            case "LoanPaymentSubmitted":
                entities.add(generateLoanPaymentEvent());
                break;
            case "CarServiceDone":
                entities.add(generateCarServiceEvent());
                break;
            case "LoanCreated":
                entities.add(generateLoanCreatedEvent());
                break;
            case "CarRegistered":
                entities.add(generateCarRegisteredEvent());
                break;
        }
        
        body.setEntities(entities);
        
        return new Event(header, body);
    }
    
    /**
     * Generate a loan payment event
     */
    private EntityUpdate generateLoanPaymentEvent() {
        Map<String, Object> attributes = new HashMap<>();
        attributes.put("id", "loan-" + random.nextInt(100000));
        attributes.put("balance", String.format("%.2f", 10000 + random.nextDouble() * 50000));
        attributes.put("lastPaidDate", OffsetDateTime.now().toString());
        attributes.put("paymentAmount", String.format("%.2f", 200 + random.nextDouble() * 800));
        attributes.put("paymentMethod", random.nextBoolean() ? "ACH" : "Check");
        
        return new EntityUpdate("Loan", "loan-" + random.nextInt(100000), attributes);
    }
    
    /**
     * Generate a car service event
     */
    private EntityUpdate generateCarServiceEvent() {
        Map<String, Object> attributes = new HashMap<>();
        attributes.put("id", "car-" + random.nextInt(100000));
        attributes.put("serviceDate", OffsetDateTime.now().toString());
        attributes.put("amountPaid", String.format("%.2f", 50 + random.nextDouble() * 500));
        attributes.put("dealerId", "dealer-" + random.nextInt(100));
        attributes.put("dealerName", "Service Center " + random.nextInt(10));
        attributes.put("mileageAtService", String.valueOf(1000 + random.nextInt(200000)));
        attributes.put("description", generateServiceDescription());
        
        return new EntityUpdate("Car", "car-" + random.nextInt(100000), attributes);
    }
    
    /**
     * Generate a loan created event
     */
    private EntityUpdate generateLoanCreatedEvent() {
        Map<String, Object> attributes = new HashMap<>();
        attributes.put("id", "loan-" + random.nextInt(100000));
        attributes.put("carId", "car-" + random.nextInt(100000));
        attributes.put("financialInstitution", FINANCIAL_INSTITUTIONS[random.nextInt(FINANCIAL_INSTITUTIONS.length)]);
        attributes.put("balance", String.format("%.2f", 15000 + random.nextDouble() * 35000));
        attributes.put("loanAmount", String.format("%.2f", 20000 + random.nextDouble() * 40000));
        attributes.put("interestRate", String.format("%.3f", 0.02 + random.nextDouble() * 0.08));
        attributes.put("termMonths", String.valueOf(36 + random.nextInt(84))); // 3-10 years
        attributes.put("startDate", OffsetDateTime.now().minusSeconds(random.nextInt(86400 * 365)).toString());
        attributes.put("status", "active");
        attributes.put("monthlyPayment", String.format("%.2f", 300 + random.nextDouble() * 700));
        
        return new EntityUpdate("Loan", "loan-" + random.nextInt(100000), attributes);
    }
    
    /**
     * Generate a car registered event
     */
    private EntityUpdate generateCarRegisteredEvent() {
        Map<String, Object> attributes = new HashMap<>();
        attributes.put("id", "car-" + random.nextInt(100000));
        attributes.put("vin", generateVIN());
        attributes.put("make", CAR_MAKES[random.nextInt(CAR_MAKES.length)]);
        attributes.put("model", CAR_MODELS[random.nextInt(CAR_MODELS.length)]);
        attributes.put("year", String.valueOf(2015 + random.nextInt(10)));
        attributes.put("color", COLORS[random.nextInt(COLORS.length)]);
        attributes.put("mileage", String.valueOf(random.nextInt(100000)));
        attributes.put("owner", "Owner " + random.nextInt(1000));
        attributes.put("registrationDate", OffsetDateTime.now().minusSeconds(random.nextInt(86400 * 365)).toString());
        
        return new EntityUpdate("Car", "car-" + random.nextInt(100000), attributes);
    }
    
    /**
     * Generate a service description
     */
    private String generateServiceDescription() {
        String[] services = {
            "Oil change and filter replacement",
            "Brake pad replacement",
            "Tire rotation and balancing",
            "Air filter replacement",
            "Transmission fluid change",
            "Coolant system flush",
            "Multi-point inspection",
            "Wheel alignment",
            "Battery replacement",
            "Spark plug replacement"
        };
        return services[random.nextInt(services.length)];
    }
    
    /**
     * Generate a VIN number
     */
    private String generateVIN() {
        StringBuilder vin = new StringBuilder();
        String chars = "ABCDEFGHJKLMNPRSTUVWXYZ0123456789";
        for (int i = 0; i < 17; i++) {
            vin.append(chars.charAt(random.nextInt(chars.length())));
        }
        return vin.toString();
    }
    
    /**
     * Generate events with specific characteristics for testing
     * @param count the number of events
     * @param eventType the specific event type
     * @param sizeKB approximate size per event in KB
     * @return list of generated events
     */
    public List<Event> generateEventsWithSize(int count, String eventType, int sizeKB) {
        logger.info("Generating {} {} events with target size {}KB each", count, eventType, sizeKB);
        
        List<Event> events = new ArrayList<>();
        for (int i = 0; i < count; i++) {
            Event event = generateEventWithSize(i, eventType, sizeKB);
            events.add(event);
        }
        
        logger.info("Generated {} events with target size", events.size());
        return events;
    }
    
    /**
     * Generate an event with specific size characteristics
     */
    private Event generateEventWithSize(int index, String eventType, int sizeKB) {
        String uuid = UUID.randomUUID().toString();
        OffsetDateTime now = OffsetDateTime.now();
        
        EventHeader header = new EventHeader(
            uuid,
            eventType,
            now.minusSeconds(random.nextInt(3600)),
            now,
            eventType
        );
        
        // Generate large attributes to reach target size
        Map<String, Object> attributes = new HashMap<>();
        attributes.put("id", "entity-" + index);
        
        // Add large text fields to reach target size
        StringBuilder largeText = new StringBuilder();
        int targetChars = (sizeKB * 1024) / 4; // Rough estimate for JSON overhead
        while (largeText.length() < targetChars) {
            largeText.append("This is a large text field to increase the event size. ");
            largeText.append("It contains multiple sentences and various characters. ");
            largeText.append("The purpose is to create events of specific sizes for testing. ");
        }
        
        attributes.put("largeTextField", largeText.toString());
        attributes.put("timestamp", now.toString());
        attributes.put("index", String.valueOf(index));
        
        EntityUpdate entity = new EntityUpdate("TestEntity", "entity-" + index, attributes);
        EventBody body = new EventBody();
        body.setEntities(List.of(entity));
        
        return new Event(header, body);
    }
}
