package com.example;

import org.apache.flink.table.api.EnvironmentSettings;
import org.apache.flink.table.api.StatementSet;
import org.apache.flink.table.api.TableEnvironment;

/**
 * Flink streaming job for routing business events from raw-event-headers to filtered topics.
 * Uses Flink Table API to create persistent streaming jobs that run independently of client sessions.
 */
public class BusinessEventsRoutingJob {
    public static void main(String[] args) {
        // Set up streaming environment
        EnvironmentSettings settings = EnvironmentSettings.newInstance()
                .inStreamingMode()
                .build();
        TableEnvironment tEnv = TableEnvironment.create(settings);

        System.out.println("Creating source and sink tables...");

        // Create source table: raw-event-headers from Kafka (Debezium CDC format)
        tEnv.executeSql(
            "CREATE TABLE IF NOT EXISTS `raw-event-headers` (" +
            "    `id` STRING," +
            "    `event_name` STRING," +
            "    `event_type` STRING," +
            "    `created_date` STRING," +
            "    `saved_date` STRING," +
            "    `header_data` STRING," +
            "    `__op` STRING," +
            "    `__table` STRING," +
            "    `__ts_ms` BIGINT" +
            ") WITH (" +
            "    'connector' = 'kafka'," +
            "    'topic' = 'raw-event-headers'," +
            "    'properties.bootstrap.servers' = 'redpanda:9092'," +
            "    'format' = 'json'," +
            "    'scan.startup.mode' = 'earliest-offset'," +
            "    'json.ignore-parse-errors' = 'true'" +
            ")"
        );

        // Create sink table: filtered-car-created-events-flink
        tEnv.executeSql(
            "CREATE TABLE IF NOT EXISTS `filtered-car-created-events-flink` (" +
            "    `key` BYTES," +
            "    `id` STRING," +
            "    `event_name` STRING," +
            "    `event_type` STRING," +
            "    `created_date` STRING," +
            "    `saved_date` STRING," +
            "    `header_data` STRING," +
            "    `__op` STRING," +
            "    `__table` STRING" +
            ") WITH (" +
            "    'connector' = 'kafka'," +
            "    'topic' = 'filtered-car-created-events-flink'," +
            "    'properties.bootstrap.servers' = 'redpanda:9092'," +
            "    'format' = 'json'," +
            "    'json.ignore-parse-errors' = 'true'," +
            "    'sink.partitioner' = 'fixed'" +
            ")"
        );

        // Create sink table: filtered-loan-created-events-flink
        tEnv.executeSql(
            "CREATE TABLE IF NOT EXISTS `filtered-loan-created-events-flink` (" +
            "    `key` BYTES," +
            "    `id` STRING," +
            "    `event_name` STRING," +
            "    `event_type` STRING," +
            "    `created_date` STRING," +
            "    `saved_date` STRING," +
            "    `header_data` STRING," +
            "    `__op` STRING," +
            "    `__table` STRING" +
            ") WITH (" +
            "    'connector' = 'kafka'," +
            "    'topic' = 'filtered-loan-created-events-flink'," +
            "    'properties.bootstrap.servers' = 'redpanda:9092'," +
            "    'format' = 'json'," +
            "    'json.ignore-parse-errors' = 'true'," +
            "    'sink.partitioner' = 'fixed'" +
            ")"
        );

        // Create sink table: filtered-loan-payment-submitted-events-flink
        tEnv.executeSql(
            "CREATE TABLE IF NOT EXISTS `filtered-loan-payment-submitted-events-flink` (" +
            "    `key` BYTES," +
            "    `id` STRING," +
            "    `event_name` STRING," +
            "    `event_type` STRING," +
            "    `created_date` STRING," +
            "    `saved_date` STRING," +
            "    `header_data` STRING," +
            "    `__op` STRING," +
            "    `__table` STRING" +
            ") WITH (" +
            "    'connector' = 'kafka'," +
            "    'topic' = 'filtered-loan-payment-submitted-events-flink'," +
            "    'properties.bootstrap.servers' = 'redpanda:9092'," +
            "    'format' = 'json'," +
            "    'json.ignore-parse-errors' = 'true'," +
            "    'sink.partitioner' = 'fixed'" +
            ")"
        );

        // Create sink table: filtered-service-events-flink
        tEnv.executeSql(
            "CREATE TABLE IF NOT EXISTS `filtered-service-events-flink` (" +
            "    `key` BYTES," +
            "    `id` STRING," +
            "    `event_name` STRING," +
            "    `event_type` STRING," +
            "    `created_date` STRING," +
            "    `saved_date` STRING," +
            "    `header_data` STRING," +
            "    `__op` STRING," +
            "    `__table` STRING" +
            ") WITH (" +
            "    'connector' = 'kafka'," +
            "    'topic' = 'filtered-service-events-flink'," +
            "    'properties.bootstrap.servers' = 'redpanda:9092'," +
            "    'format' = 'json'," +
            "    'json.ignore-parse-errors' = 'true'," +
            "    'sink.partitioner' = 'fixed'" +
            ")"
        );

        System.out.println("Tables created. Bundling INSERT statements...");

        // Bundle INSERTs into one job via StatementSet for efficient parallel execution
        StatementSet stmtSet = tEnv.createStatementSet();

        // INSERT: Car Created Events Filter
        stmtSet.addInsertSql(
            "INSERT INTO `filtered-car-created-events-flink` " +
            "SELECT " +
            "    CAST(`id` AS BYTES) AS `key`," +
            "    `id`," +
            "    `event_name`," +
            "    `event_type`," +
            "    `created_date`," +
            "    `saved_date`," +
            "    `header_data`," +
            "    `__op`," +
            "    `__table` " +
            "FROM `raw-event-headers` " +
            "WHERE `event_type` = 'CarCreated' AND `__op` = 'c'"
        );

        // INSERT: Loan Created Events Filter
        stmtSet.addInsertSql(
            "INSERT INTO `filtered-loan-created-events-flink` " +
            "SELECT " +
            "    CAST(`id` AS BYTES) AS `key`," +
            "    `id`," +
            "    `event_name`," +
            "    `event_type`," +
            "    `created_date`," +
            "    `saved_date`," +
            "    `header_data`," +
            "    `__op`," +
            "    `__table` " +
            "FROM `raw-event-headers` " +
            "WHERE `event_type` = 'LoanCreated' AND `__op` = 'c'"
        );

        // INSERT: Loan Payment Submitted Events Filter
        stmtSet.addInsertSql(
            "INSERT INTO `filtered-loan-payment-submitted-events-flink` " +
            "SELECT " +
            "    CAST(`id` AS BYTES) AS `key`," +
            "    `id`," +
            "    `event_name`," +
            "    `event_type`," +
            "    `created_date`," +
            "    `saved_date`," +
            "    `header_data`," +
            "    `__op`," +
            "    `__table` " +
            "FROM `raw-event-headers` " +
            "WHERE `event_type` = 'LoanPaymentSubmitted' AND `__op` = 'c'"
        );

        // INSERT: Service Events Filter
        stmtSet.addInsertSql(
            "INSERT INTO `filtered-service-events-flink` " +
            "SELECT " +
            "    CAST(`id` AS BYTES) AS `key`," +
            "    `id`," +
            "    `event_name`," +
            "    `event_type`," +
            "    `created_date`," +
            "    `saved_date`," +
            "    `header_data`," +
            "    `__op`," +
            "    `__table` " +
            "FROM `raw-event-headers` " +
            "WHERE `event_type` = 'CarServiceDone' AND `__op` = 'c'"
        );

        System.out.println("Executing streaming job...");
        System.out.println("Job will run continuously. Press Ctrl+C to stop.");

        // Execute as a single persistent streaming job
        // This blocks and keeps the job running continuously
        stmtSet.execute();
    }
}


