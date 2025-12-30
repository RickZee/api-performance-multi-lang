# V2 Active Filters API Fix Summary

## Issue
The `/api/v1/filters/active?version=v2` endpoint was returning an empty array `[]` even though the database contained 4 approved, enabled filters for v2.

## Root Causes Identified

### 1. Query Parameter Name Mismatch
**Problem**: The `@RequestParam` annotation didn't specify the query parameter name, so Spring was looking for `schemaVersion` instead of `version`.

**Fix**: Added `value = "version"` to the `@RequestParam` annotation:
```java
@RequestParam(value = "version", required = false, defaultValue = "v1") String schemaVersion
```

### 2. Query Included Pending Approval Filters
**Problem**: The JPA query was returning all enabled filters that weren't deleted, including `pending_approval` ones. Active filters should only include `approved` or `deployed` filters.

**Fix**: Changed the query from:
```java
AND f.status NOT IN ('deleted', 'pending_deletion')
```
to:
```java
AND f.status IN ('approved', 'deployed')
```

## Files Modified

1. **FilterController.java** (line 331):
   - Added `value = "version"` to `@RequestParam` annotation

2. **FilterRepository.java** (line 39-40):
   - Changed query to only include `approved` or `deployed` status filters

3. **FilterStorageService.java** (line 256-259):
   - Added debug logging to track filter retrieval

## Verification

✅ **Before Fix**: 
- API returned `[]` for v2
- Database had 4 approved filters

✅ **After Fix**:
- API returns 4 active filters for v2
- All filters have `status: "approved"` and `enabled: true`
- Logs show: "Found 4 active filter entities for schema version v2"

## Test Results

```bash
$ curl -s "http://localhost:8080/api/v1/filters/active?version=v2" | jq 'length'
4

$ curl -s "http://localhost:8080/api/v1/filters/active?version=v2" | jq '.[0]'
{
  "id": "car-created-events-v2-1767118891602",
  "status": "approved",
  "enabled": true,
  "outputTopic": "filtered-car-created-events-v2-spring",
  ...
}
```

## Next Steps

1. ✅ V2 filters API is now working
2. ⏭️ Start V2 stream processor and verify it fetches filters
3. ⏭️ Run full integration tests
4. ⏭️ Verify end-to-end V2 event processing

