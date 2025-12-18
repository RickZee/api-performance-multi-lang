# Resilience Testing Guide

This guide provides detailed procedures for resilience testing, including recovery scenarios, chaos engineering, and disaster recovery validation.

## Recovery Testing

### Service Restart Scenarios

**Test Objective**: Verify that services can recover after restart without data loss.

**Test Procedure**:
1. Publish events before restart
2. Restart service (Spring Boot or Flink)
3. Publish events after restart
4. Verify all events are processed
5. Verify no duplicate processing

**Success Criteria**:
- All events eventually processed
- No data loss
- No duplicate events
- Recovery time < 1 minute (RTO)

**Implementation**:
```java
@Test
void testSpringBootRestartRecovery() {
    // Publish events before restart
    publishEvents(10);
    
    // Simulate restart
    restartService();
    
    // Publish events after restart
    publishEvents(10);
    
    // Verify all events processed
    verifyAllEventsProcessed();
}
```

### State Recovery Validation

**Test Objective**: Verify Kafka Streams state stores recover correctly after restart.

**Test Procedure**:
1. Publish events that create state
2. Restart service
3. Publish more events
4. Verify state is maintained correctly
5. Verify processing continues correctly

**Key Considerations**:
- State stores backed by changelog topics
- Offsets committed correctly
- State recovery from changelog topics

### Data Loss Verification

**Test Objective**: Ensure no data loss during recovery scenarios.

**Test Procedure**:
1. Publish events with unique IDs
2. Trigger recovery scenario
3. Verify all events are eventually processed
4. Count unique event IDs
5. Compare published vs. processed counts

**Success Criteria**:
- 100% of events processed
- No missing events
- Event order maintained (if required)

## Chaos Engineering

### Pod Termination Tests

**Test Objective**: Verify Kubernetes pod termination and recreation.

**Test Procedure**:
1. Deploy service to Kubernetes
2. Identify pod running service
3. Terminate pod: `kubectl delete pod <pod-name>`
4. Verify Kubernetes recreates pod
5. Verify service resumes processing
6. Measure recovery time

**Success Criteria**:
- Pod recreated automatically
- Service resumes processing
- No data loss
- Recovery time < 2 minutes

**Implementation**:
```java
@Test
void testPodTermination() {
    // Get pod name
    String podName = getServicePodName();
    
    // Terminate pod
    kubectl.deletePod(podName);
    
    // Wait for recreation
    waitForPodReady();
    
    // Verify processing resumes
    verifyProcessingResumes();
}
```

### Network Partition Simulation

**Test Objective**: Verify system behavior during network issues.

**Test Procedure**:
1. Establish baseline processing
2. Simulate network partition (block network traffic)
3. Publish events during partition
4. Restore network connectivity
5. Verify events are eventually processed
6. Measure recovery time

**Success Criteria**:
- Events queued during partition
- Events processed after recovery
- No data loss
- Recovery time acceptable

**Tools**:
- Network manipulation tools (iptables, tc)
- Chaos Mesh for Kubernetes
- Network emulation tools

### Resource Exhaustion Scenarios

**Test Objective**: Verify graceful handling of resource constraints.

**Memory Pressure**:
1. Limit container memory
2. Trigger high memory usage
3. Verify graceful handling
4. Verify no crashes

**CPU Pressure**:
1. Limit container CPU
2. Trigger high CPU usage
3. Verify throttling
4. Verify processing continues

**Disk Space**:
1. Fill state store disk
2. Verify graceful handling
3. Verify error reporting
4. Verify recovery after cleanup

## Disaster Recovery

### RTO/RPO Validation

**Recovery Time Objective (RTO)**: Target time to resume processing after failure.

**Test Procedure**:
1. Mark failure time
2. Trigger failure scenario
3. Measure time to resume processing
4. Compare against RTO target (< 1 minute)

**Recovery Point Objective (RPO)**: Maximum acceptable data loss.

**Test Procedure**:
1. Publish events before failure
2. Trigger failure
3. Measure events lost
4. Compare against RPO target (0 events)

### Failover Procedures

**Test Objective**: Verify automatic failover to backup systems.

**Test Procedure**:
1. Deploy primary and backup systems
2. Trigger primary system failure
3. Verify automatic failover
4. Verify backup system takes over
5. Measure failover time

**Success Criteria**:
- Automatic failover
- No data loss
- Failover time < 30 seconds
- Seamless transition

### Recovery Playbooks

**Documented Procedures**:
1. **Service Restart**: Step-by-step restart procedure
2. **State Recovery**: How to recover state stores
3. **Offset Reset**: When and how to reset offsets
4. **Data Replay**: How to replay events if needed
5. **Rollback Procedure**: How to rollback to previous version

**Test Procedure**:
1. Follow recovery playbook
2. Document actual recovery time
3. Verify all steps work correctly
4. Update playbook if needed

## Test Execution

### Pre-Test Checklist

- [ ] Services deployed and healthy
- [ ] Monitoring enabled
- [ ] Backup systems ready (if applicable)
- [ ] Recovery playbooks reviewed
- [ ] Test data prepared
- [ ] Baseline metrics recorded

### Test Execution Sequence

1. **Baseline**: Establish normal operation baseline
2. **Failure Injection**: Trigger failure scenario
3. **Observation**: Monitor system behavior
4. **Recovery**: Trigger recovery procedure
5. **Verification**: Verify system recovered correctly
6. **Documentation**: Document results and lessons learned

### Post-Test Actions

- [ ] Verify all events processed
- [ ] Check for data loss
- [ ] Review recovery time
- [ ] Document issues found
- [ ] Update recovery playbooks
- [ ] Update monitoring alerts

## Common Failure Scenarios

### Kafka Broker Failure

**Scenario**: Kafka broker becomes unavailable

**Expected Behavior**:
- Producers/consumers retry
- Events queued locally
- Automatic reconnection
- Events processed after recovery

**Test**:
```java
@Test
void testKafkaBrokerFailure() {
    // Simulate broker failure
    blockKafkaAccess();
    
    // Publish events (should queue)
    publishEvents(100);
    
    // Restore access
    restoreKafkaAccess();
    
    // Verify events processed
    verifyAllEventsProcessed();
}
```

### Service Crash

**Scenario**: Service crashes unexpectedly

**Expected Behavior**:
- Kubernetes restarts pod
- State recovered from changelog topics
- Processing resumes
- No data loss

### Network Partition

**Scenario**: Network connectivity lost

**Expected Behavior**:
- Events queued
- Automatic reconnection
- Events processed after recovery
- No data loss

## Resilience Test Checklist

- [ ] Service restart recovery tested
- [ ] State recovery validated
- [ ] Data loss verification passed
- [ ] RTO measured and documented
- [ ] RPO validated (0 data loss)
- [ ] Pod termination tested
- [ ] Network partition tested
- [ ] Resource exhaustion tested
- [ ] Failover procedures validated
- [ ] Recovery playbooks tested
- [ ] Monitoring alerts configured
- [ ] Documentation updated

## Best Practices

1. **Test Regularly**: Run resilience tests regularly (weekly/monthly)
2. **Automate**: Automate resilience tests in CI/CD
3. **Document**: Document all failure scenarios and recovery procedures
4. **Monitor**: Monitor recovery times and update RTO/RPO targets
5. **Improve**: Continuously improve recovery procedures based on test results
6. **Train**: Train team on recovery procedures
7. **Review**: Review and update recovery playbooks regularly
