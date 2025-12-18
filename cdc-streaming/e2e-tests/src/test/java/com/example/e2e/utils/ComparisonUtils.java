package com.example.e2e.utils;

import com.example.e2e.model.EventHeader;
import org.assertj.core.api.Assertions;

import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.stream.Collectors;

/**
 * Utility class for comparing events and asserting parity.
 */
public class ComparisonUtils {
    
    /**
     * Compare two events field-by-field.
     */
    public static boolean compareEventStructures(EventHeader event1, EventHeader event2) {
        if (event1 == null || event2 == null) {
            return event1 == event2;
        }
        
        return Objects.equals(event1.getId(), event2.getId()) &&
               Objects.equals(event1.getEventName(), event2.getEventName()) &&
               Objects.equals(event1.getEventType(), event2.getEventType()) &&
               Objects.equals(event1.getCreatedDate(), event2.getCreatedDate()) &&
               Objects.equals(event1.getSavedDate(), event2.getSavedDate()) &&
               Objects.equals(event1.getHeaderData(), event2.getHeaderData()) &&
               Objects.equals(event1.getOp(), event2.getOp()) &&
               Objects.equals(event1.getTable(), event2.getTable());
    }
    
    /**
     * Compare two batches of events.
     */
    public static ComparisonResult compareEventBatches(List<EventHeader> batch1, List<EventHeader> batch2) {
        ComparisonResult result = new ComparisonResult();
        result.setBatch1Size(batch1.size());
        result.setBatch2Size(batch2.size());
        result.setSizeMatch(batch1.size() == batch2.size());
        
        if (!result.isSizeMatch()) {
            return result;
        }
        
        // Create maps by event ID for comparison
        Map<String, EventHeader> map1 = batch1.stream()
            .collect(Collectors.toMap(EventHeader::getId, e -> e));
        Map<String, EventHeader> map2 = batch2.stream()
            .collect(Collectors.toMap(EventHeader::getId, e -> e));
        
        // Check if all IDs match
        result.setIdsMatch(map1.keySet().equals(map2.keySet()));
        
        if (!result.isIdsMatch()) {
            return result;
        }
        
        // Compare each event
        boolean allMatch = true;
        for (String id : map1.keySet()) {
            EventHeader e1 = map1.get(id);
            EventHeader e2 = map2.get(id);
            if (!compareEventStructures(e1, e2)) {
                allMatch = false;
                result.addMismatch(id, "Event structures differ");
            }
        }
        
        result.setAllEventsMatch(allMatch);
        return result;
    }
    
    /**
     * Assert that Flink and Spring Boot events are identical.
     */
    public static void assertEventParity(List<EventHeader> flinkEvents, List<EventHeader> springEvents) {
        ComparisonResult result = compareEventBatches(flinkEvents, springEvents);
        
        Assertions.assertThat(result.isSizeMatch())
            .as("Event counts should match: Flink=%d, Spring=%d", result.getBatch1Size(), result.getBatch2Size())
            .isTrue();
        
        Assertions.assertThat(result.isIdsMatch())
            .as("Event IDs should match")
            .isTrue();
        
        Assertions.assertThat(result.isAllEventsMatch())
            .as("All events should have identical structures. Mismatches: %s", result.getMismatches())
            .isTrue();
    }
    
    /**
     * Result of event batch comparison.
     */
    public static class ComparisonResult {
        private int batch1Size;
        private int batch2Size;
        private boolean sizeMatch;
        private boolean idsMatch;
        private boolean allEventsMatch;
        private Map<String, String> mismatches = new java.util.HashMap<>();
        
        public void addMismatch(String eventId, String reason) {
            mismatches.put(eventId, reason);
        }
        
        // Getters and setters
        public int getBatch1Size() { return batch1Size; }
        public void setBatch1Size(int batch1Size) { this.batch1Size = batch1Size; }
        
        public int getBatch2Size() { return batch2Size; }
        public void setBatch2Size(int batch2Size) { this.batch2Size = batch2Size; }
        
        public boolean isSizeMatch() { return sizeMatch; }
        public void setSizeMatch(boolean sizeMatch) { this.sizeMatch = sizeMatch; }
        
        public boolean isIdsMatch() { return idsMatch; }
        public void setIdsMatch(boolean idsMatch) { this.idsMatch = idsMatch; }
        
        public boolean isAllEventsMatch() { return allEventsMatch; }
        public void setAllEventsMatch(boolean allEventsMatch) { this.allEventsMatch = allEventsMatch; }
        
        public Map<String, String> getMismatches() { return mismatches; }
    }
}
