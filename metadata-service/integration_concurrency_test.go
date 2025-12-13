package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"metadata-service/internal/testutil"
)

func TestConcurrentValidations(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	reqBody := map[string]interface{}{
		"event": event,
	}
	body, _ := json.Marshal(reqBody)

	var wg sync.WaitGroup
	numGoroutines := 50
	errors := make(chan error, numGoroutines)

	for i := 0; i < numGoroutines; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()

			router := setupTestRouter()
			router.ServeHTTP(w, req)

			if w.Code != http.StatusOK {
				errors <- &testError{message: "Expected status 200"}
			}
		}()
	}

	wg.Wait()
	close(errors)

	errorCount := 0
	for err := range errors {
		if err != nil {
			errorCount++
		}
	}

	if errorCount > 0 {
		t.Errorf("Concurrent validations should not fail, got %d errors", errorCount)
	}
}

func TestConcurrentBulkValidations(t *testing.T) {
	validEvent := testutil.ValidCarCreatedEvent()
	reqBody := map[string]interface{}{
		"events": []interface{}{validEvent, validEvent},
	}
	body, _ := json.Marshal(reqBody)

	var wg sync.WaitGroup
	numGoroutines := 30
	errors := make(chan error, numGoroutines)

	for i := 0; i < numGoroutines; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			req := httptest.NewRequest("POST", "/api/v1/validate/bulk", bytes.NewBuffer(body))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()

			router := setupTestRouter()
			router.ServeHTTP(w, req)

			if w.Code != http.StatusOK {
				errors <- &testError{message: "Expected status 200"}
			}
		}()
	}

	wg.Wait()
	close(errors)

	errorCount := 0
	for err := range errors {
		if err != nil {
			errorCount++
		}
	}

	if errorCount > 0 {
		t.Errorf("Concurrent bulk validations should not fail, got %d errors", errorCount)
	}
}

func TestConcurrentGetSchema(t *testing.T) {
	var wg sync.WaitGroup
	numGoroutines := 50
	errors := make(chan error, numGoroutines)

	for i := 0; i < numGoroutines; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			req := httptest.NewRequest("GET", "/api/v1/schemas/v1?type=event", nil)
			w := httptest.NewRecorder()

			router := setupTestRouter()
			router.ServeHTTP(w, req)

			if w.Code != http.StatusOK {
				errors <- &testError{message: "Expected status 200"}
			}
		}()
	}

	wg.Wait()
	close(errors)

	errorCount := 0
	for err := range errors {
		if err != nil {
			errorCount++
		}
	}

	if errorCount > 0 {
		t.Errorf("Concurrent schema retrieval should not fail, got %d errors", errorCount)
	}
}

func TestConcurrentGetVersions(t *testing.T) {
	var wg sync.WaitGroup
	numGoroutines := 50
	errors := make(chan error, numGoroutines)

	for i := 0; i < numGoroutines; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			req := httptest.NewRequest("GET", "/api/v1/schemas/versions", nil)
			w := httptest.NewRecorder()

			router := setupTestRouter()
			router.ServeHTTP(w, req)

			if w.Code != http.StatusOK {
				errors <- &testError{message: "Expected status 200"}
			}
		}()
	}

	wg.Wait()
	close(errors)

	errorCount := 0
	for err := range errors {
		if err != nil {
			errorCount++
		}
	}

	if errorCount > 0 {
		t.Errorf("Concurrent version retrieval should not fail, got %d errors", errorCount)
	}
}

func TestConcurrentHealthChecks(t *testing.T) {
	var wg sync.WaitGroup
	numGoroutines := 100
	errors := make(chan error, numGoroutines)

	for i := 0; i < numGoroutines; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			req := httptest.NewRequest("GET", "/api/v1/health", nil)
			w := httptest.NewRecorder()

			router := setupTestRouter()
			router.ServeHTTP(w, req)

			if w.Code != http.StatusOK {
				errors <- &testError{message: "Expected status 200"}
			}
		}()
	}

	wg.Wait()
	close(errors)

	errorCount := 0
	for err := range errors {
		if err != nil {
			errorCount++
		}
	}

	if errorCount > 0 {
		t.Errorf("Concurrent health checks should not fail, got %d errors", errorCount)
	}
}

func TestConcurrentMixedOperations(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	reqBody := map[string]interface{}{
		"event": event,
	}
	body, _ := json.Marshal(reqBody)

	var wg sync.WaitGroup
	errors := make(chan error, 100)

	// Mix of different operations
	operations := []func(){
		func() {
			req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()
			router := setupTestRouter()
			router.ServeHTTP(w, req)
			if w.Code != http.StatusOK {
				errors <- &testError{message: "Validation failed"}
			}
		},
		func() {
			req := httptest.NewRequest("GET", "/api/v1/schemas/v1", nil)
			w := httptest.NewRecorder()
			router := setupTestRouter()
			router.ServeHTTP(w, req)
			if w.Code != http.StatusOK {
				errors <- &testError{message: "Get schema failed"}
			}
		},
		func() {
			req := httptest.NewRequest("GET", "/api/v1/schemas/versions", nil)
			w := httptest.NewRecorder()
			router := setupTestRouter()
			router.ServeHTTP(w, req)
			if w.Code != http.StatusOK {
				errors <- &testError{message: "Get versions failed"}
			}
		},
		func() {
			req := httptest.NewRequest("GET", "/api/v1/health", nil)
			w := httptest.NewRecorder()
			router := setupTestRouter()
			router.ServeHTTP(w, req)
			if w.Code != http.StatusOK {
				errors <- &testError{message: "Health check failed"}
			}
		},
	}

	for i := 0; i < 25; i++ {
		for _, op := range operations {
			wg.Add(1)
			go func(operation func()) {
				defer wg.Done()
				operation()
			}(op)
		}
	}

	wg.Wait()
	close(errors)

	errorCount := 0
	for err := range errors {
		if err != nil {
			errorCount++
		}
	}

	if errorCount > 0 {
		t.Errorf("Concurrent mixed operations should not fail, got %d errors", errorCount)
	}
}

func TestConcurrentValidationWithCacheReload(t *testing.T) {
	event := testutil.ValidCarCreatedEvent()
	reqBody := map[string]interface{}{
		"event": event,
	}
	body, _ := json.Marshal(reqBody)

	var wg sync.WaitGroup
	numGoroutines := 20
	errors := make(chan error, numGoroutines)

	// Invalidate cache in the middle
	go func() {
		time.Sleep(100 * time.Millisecond)
		testCache.Invalidate("v1")
	}()

	for i := 0; i < numGoroutines; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			req := httptest.NewRequest("POST", "/api/v1/validate", bytes.NewBuffer(body))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()

			router := setupTestRouter()
			router.ServeHTTP(w, req)

			if w.Code != http.StatusOK {
				errors <- &testError{message: "Expected status 200"}
			}
		}()
	}

	wg.Wait()
	close(errors)

	errorCount := 0
	for err := range errors {
		if err != nil {
			errorCount++
		}
	}

	if errorCount > 0 {
		t.Errorf("Concurrent validations during cache reload should not fail, got %d errors", errorCount)
	}
}

type testError struct {
	message string
}

func (e *testError) Error() string {
	return e.message
}
