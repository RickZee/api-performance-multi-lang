package com.example.metadata.testutil;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

public class TestRepoSetup {
    
    public static String setupTestRepo(String baseDir) throws IOException {
        Path repoDir = Paths.get(baseDir, "test-schema-repo");
        Files.createDirectories(repoDir);
        
        // Create v1 schemas directory structure
        Path v1EventDir = repoDir.resolve("schemas").resolve("v1").resolve("event");
        Path v1EntityDir = repoDir.resolve("schemas").resolve("v1").resolve("entity");
        Files.createDirectories(v1EventDir);
        Files.createDirectories(v1EntityDir);
        
        // Write event-header.json
        String eventHeader = """
            {
              "$schema": "https://json-schema.org/draft/2020-12/schema",
              "$id": "https://example.com/schemas/event/event-header.json",
              "title": "Event Header Schema",
              "type": "object",
              "properties": {
                "uuid": {
                  "type": "string",
                  "format": "uuid"
                },
                "eventName": {
                  "type": "string"
                },
                "eventType": {
                  "type": "string",
                  "enum": ["CarCreated", "LoanCreated", "LoanPaymentSubmitted", "CarServiceDone"]
                },
                "createdDate": {
                  "type": "string",
                  "format": "date-time"
                },
                "savedDate": {
                  "type": "string",
                  "format": "date-time"
                }
              },
              "required": ["uuid", "eventName", "eventType", "createdDate", "savedDate"],
              "additionalProperties": false
            }
            """;
        Files.writeString(v1EventDir.resolve("event-header.json"), eventHeader);
        
        // Write entity-header.json
        String entityHeader = """
            {
              "$schema": "https://json-schema.org/draft/2020-12/schema",
              "$id": "https://example.com/schemas/entity/entity-header.json",
              "title": "Entity Header Schema",
              "type": "object",
              "properties": {
                "entityId": {
                  "type": "string"
                },
                "entityType": {
                  "type": "string",
                  "enum": ["Car", "Loan", "LoanPayment", "ServiceRecord"]
                },
                "createdAt": {
                  "type": "string",
                  "format": "date-time"
                },
                "updatedAt": {
                  "type": "string",
                  "format": "date-time"
                }
              },
              "required": ["entityId", "entityType", "createdAt", "updatedAt"],
              "additionalProperties": false
            }
            """;
        Files.writeString(v1EntityDir.resolve("entity-header.json"), entityHeader);
        
        // Write car.json
        String carSchema = """
            {
              "$schema": "https://json-schema.org/draft/2020-12/schema",
              "$id": "https://example.com/schemas/entity/car.json",
              "title": "Car Entity Schema",
              "type": "object",
              "properties": {
                "entityHeader": {
                  "$ref": "entity-header.json"
                },
                "id": {
                  "type": "string"
                },
                "vin": {
                  "type": "string",
                  "pattern": "^[A-HJ-NPR-Z0-9]{17}$"
                },
                "make": {
                  "type": "string"
                },
                "model": {
                  "type": "string"
                },
                "year": {
                  "type": "integer",
                  "minimum": 1900,
                  "maximum": 2030
                },
                "color": {
                  "type": "string"
                },
                "mileage": {
                  "type": "integer",
                  "minimum": 0
                }
              },
              "required": ["entityHeader", "id", "vin", "make", "model", "year", "color", "mileage"],
              "additionalProperties": false
            }
            """;
        Files.writeString(v1EntityDir.resolve("car.json"), carSchema);
        
        // Write event.json
        String eventSchema = """
            {
              "$schema": "https://json-schema.org/draft/2020-12/schema",
              "$id": "https://example.com/schemas/event/event.json",
              "title": "Event Schema",
              "type": "object",
              "properties": {
                "eventHeader": {
                  "$ref": "event-header.json"
                },
                "entities": {
                  "type": "array",
                  "items": {
                    "oneOf": [
                      {
                        "$ref": "../entity/car.json"
                      }
                    ]
                  },
                  "minItems": 1
                }
              },
              "required": ["eventHeader", "entities"],
              "additionalProperties": false
            }
            """;
        Files.writeString(v1EventDir.resolve("event.json"), eventSchema);
        
        return repoDir.toString();
    }
    
    public static void cleanupTestRepo(String repoDir) throws IOException {
        Path path = Paths.get(repoDir);
        if (Files.exists(path)) {
            deleteDirectory(path.toFile());
        }
    }
    
    private static void deleteDirectory(File directory) throws IOException {
        if (directory.exists()) {
            File[] files = directory.listFiles();
            if (files != null) {
                for (File file : files) {
                    if (file.isDirectory()) {
                        deleteDirectory(file);
                    } else {
                        file.delete();
                    }
                }
            }
            directory.delete();
        }
    }
}
