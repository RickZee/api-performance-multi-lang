package main

import (
	"bytes"
	"encoding/json"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"go.uber.org/zap"
	"metadata-service/internal/cache"
	syncservice "metadata-service/internal/sync"
	"metadata-service/internal/testutil"
	"metadata-service/internal/validator"
)

var (
	benchmarkCache     *cache.SchemaCache
	benchmarkValidator *validator.JSONSchemaValidator
	benchmarkEvent     map[string]interface{}
	benchmarkGitSync   *syncservice.GitSync
)

func initBenchmark() {
	tempDir, _ := os.MkdirTemp("", "benchmark-*")
	defer os.RemoveAll(tempDir)

	repoDir, _ := testutil.SetupTestRepo(tempDir)
	defer testutil.CleanupTestRepo(repoDir)

	cacheDir := filepath.Join(tempDir, "cache")
	logger, _ := zap.NewDevelopment()

	gitSync := syncservice.NewGitSync(repoDir, "main", cacheDir, 1*time.Minute, logger)
	gitSync.Start()
	defer gitSync.Stop()
	time.Sleep(500 * time.Millisecond)

	benchmarkCache = cache.NewSchemaCache(cacheDir, logger)
	benchmarkValidator = validator.NewJSONSchemaValidator(logger)
	benchmarkEvent = testutil.ValidCarCreatedEvent()
	benchmarkGitSync = gitSync
}

func BenchmarkValidateEvent(b *testing.B) {
	if benchmarkCache == nil {
		initBenchmark()
	}

	cachedSchema, _ := benchmarkCache.LoadVersion("v1", benchmarkGitSync.GetLocalDir())

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		benchmarkValidator.ValidateEvent(
			benchmarkEvent,
			cachedSchema.EventSchema,
			cachedSchema.EntitySchemas,
			benchmarkGitSync.GetLocalDir(),
		)
	}
}

func BenchmarkValidateEvent_WithCacheMiss(b *testing.B) {
	if benchmarkCache == nil {
		initBenchmark()
	}

	// Invalidate cache to force reload
	benchmarkCache.Invalidate("v1")

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		benchmarkCache.LoadVersion("v1", benchmarkGitSync.GetLocalDir())
	}
}

func BenchmarkValidateBulkEvents(b *testing.B) {
	if benchmarkCache == nil {
		initBenchmark()
	}

	events := make([]interface{}, 100)
	for i := range events {
		events[i] = testutil.ValidCarCreatedEvent()
	}

	reqBody := map[string]interface{}{
		"events": events,
	}

	body, _ := json.Marshal(reqBody)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		req := httptest.NewRequest("POST", "/api/v1/validate/bulk", bytes.NewBuffer(body))
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()

		router := setupTestRouter()
		router.ServeHTTP(w, req)
	}
}

func BenchmarkReferenceResolution(b *testing.B) {
	if benchmarkCache == nil {
		initBenchmark()
	}

	cachedSchema, _ := benchmarkCache.LoadVersion("v1", benchmarkGitSync.GetLocalDir())

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		resolver := validator.NewReferenceResolver(
			benchmarkGitSync.GetLocalDir(),
			cachedSchema.EntitySchemas,
			zap.NewNop(),
		)
		resolver.SetVersion("v1")
		resolver.ResolveSchema(cachedSchema.EventSchema)
	}
}

func BenchmarkSchemaCache_LoadVersion(b *testing.B) {
	if benchmarkCache == nil {
		initBenchmark()
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		benchmarkCache.LoadVersion("v1", benchmarkGitSync.GetLocalDir())
	}
}

func BenchmarkSchemaCache_GetVersions(b *testing.B) {
	if benchmarkCache == nil {
		initBenchmark()
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		benchmarkCache.GetVersions(benchmarkGitSync.GetLocalDir())
	}
}

func BenchmarkConcurrentValidations(b *testing.B) {
	if benchmarkCache == nil {
		initBenchmark()
	}

	cachedSchema, _ := benchmarkCache.LoadVersion("v1", benchmarkGitSync.GetLocalDir())

	b.ResetTimer()
	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			benchmarkValidator.ValidateEvent(
				benchmarkEvent,
				cachedSchema.EventSchema,
				cachedSchema.EntitySchemas,
				benchmarkGitSync.GetLocalDir(),
			)
		}
	})
}

