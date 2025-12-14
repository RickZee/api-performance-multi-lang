# Payment and Service Events Failure Investigation

## Problem Statement
Loan Payment Submitted and Car Service Done events are showing 0% success rate (0/5) in k6 tests, while Car Created and Loan Created events show partial success.

## Test Results
From latest k6 test run:
- **Car Created**: 14/5 (some succeeded, some k6 retries)
- **Loan Created**: 1/5 (very few succeeded)  
- **Loan Payment Submitted**: 0/5 (all failed)
- **Car Service Done**: 0/5 (all failed)

## Root Cause Analysis

### 1. Event Dependencies
Both Payment and Service events have dependencies:
- **Loan Payment**: References `loanId` from Loan Created events
- **Car Service**: References `carId` from Car Created events

### 2. Transaction Conflict Cascade
The issue appears to be a **cascade effect** of OC000 transaction conflicts:

1. **Car Created events** fail with OC000 (only partial success)
2. **Loan Created events** fail with OC000 (very few succeed)
3. **Loan Payment events** fail because:
   - They reference loans that may not exist (if Loan Created failed)
   - Even if loans exist, Payment events themselves hit OC000 conflicts
4. **Car Service events** fail because:
   - They reference cars that may not exist (if Car Created failed)
   - Even if cars exist, Service events themselves hit OC000 conflicts

### 3. Evidence from Logs
- No specific logs found for Payment/Service events in CloudWatch
- This suggests they're either:
  1. Failing before reaching Lambda (unlikely - would see 4xx errors)
  2. Failing with OC000 errors that exhaust all retries (likely)
  3. Not being sent at all (unlikely - k6 shows they're being sent)

### 4. k6 Script Analysis
The k6 script sends events in this order:
- Iterations 0-4: Car Created (5 events)
- Iterations 5-9: Loan Created (5 events)  
- Iterations 10-14: Loan Payment (5 events)
- Iterations 15-19: Car Service (5 events)

Payment events reference `data.loanIds[loanIndex]` and Service events reference `data.carIds[carIndex]`, so the IDs should exist even if the database records don't (due to OC000 failures).

## Conclusion

**Primary Issue**: Payment and Service events are failing due to the same OC000 transaction conflicts affecting all event types. The retry logic is working (we see "all retries exhausted" messages), but all 5 retry attempts are failing for these events.

**Secondary Issue**: There may be a dependency problem where Payment events reference loans that don't exist in the database (because Loan Created events failed), but this would typically result in a different error (foreign key violation or validation error), not OC000.

## Recommendations

1. **Increase Retry Parameters**: 
   - Increase max retries from 5 to 10
   - Increase backoff delays (100ms-2s → 200ms-5s)
   - Add more jitter to spread retries further apart

2. **Investigate Dependency Validation**:
   - Check if Payment/Service events validate that referenced loans/cars exist
   - If validation exists, ensure it handles missing references gracefully
   - If no validation, consider adding it to provide better error messages

3. **Sequential Event Processing**:
   - Consider sending events sequentially (wait for Car/Loan to succeed before sending Payment/Service)
   - Or add delays between event types to allow transactions to commit

4. **Monitor Specific Event Types**:
   - Add detailed logging for Payment/Service events to see exact failure reasons
   - Check if they're hitting different error paths than Car/Loan events

5. **Database-Level Investigation**:
   - Check if `loan_payment_entities` and `service_record_entities` tables have different conflict patterns
   - Verify indexes aren't causing additional contention

## Next Steps

1. Add specific logging for Payment/Service events to capture exact error messages
2. Run a test with only Payment events (after ensuring loans exist) to isolate the issue
3. Check if Payment/Service events have different transaction patterns that cause more conflicts
4. Consider implementing event ordering or dependency checking
