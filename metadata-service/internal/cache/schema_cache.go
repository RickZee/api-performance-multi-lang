package cache

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"go.uber.org/zap"
)

type SchemaCache struct {
	cacheDir string
	cache    map[string]*CachedSchema
	mu       sync.RWMutex
	logger   *zap.Logger
}

type CachedSchema struct {
	Version     string
	Schema      map[string]interface{}
	EventSchema map[string]interface{}
	EntitySchemas map[string]map[string]interface{}
	LoadedAt    time.Time
}

func NewSchemaCache(cacheDir string, logger *zap.Logger) *SchemaCache {
	return &SchemaCache{
		cacheDir: cacheDir,
		cache:    make(map[string]*CachedSchema),
		logger:    logger,
	}
}

func (sc *SchemaCache) LoadVersion(version, schemasDir string) (*CachedSchema, error) {
	sc.mu.RLock()
	cached, exists := sc.cache[version]
	sc.mu.RUnlock()

	if exists {
		// Check if cache is still valid (reload if older than 1 hour)
		if time.Since(cached.LoadedAt) < time.Hour {
			return cached, nil
		}
	}

	sc.mu.Lock()
	defer sc.mu.Unlock()

	// Double-check after acquiring write lock
	if cached, exists := sc.cache[version]; exists && time.Since(cached.LoadedAt) < time.Hour {
		return cached, nil
	}

	// Load from disk
	schema, err := sc.loadFromDisk(version, schemasDir)
	if err != nil {
		return nil, fmt.Errorf("failed to load schema version %s: %w", version, err)
	}

	sc.cache[version] = schema
	return schema, nil
}

func (sc *SchemaCache) loadFromDisk(version, schemasDir string) (*CachedSchema, error) {
	// Check if schemasDir contains a "schemas" subdirectory (git repo structure)
	schemasSubDir := filepath.Join(schemasDir, "schemas")
	if _, err := os.Stat(schemasSubDir); err == nil {
		schemasDir = schemasSubDir
	}
	
	versionDir := filepath.Join(schemasDir, version)
	if _, err := os.Stat(versionDir); os.IsNotExist(err) {
		return nil, fmt.Errorf("version directory not found: %s", versionDir)
	}

	cached := &CachedSchema{
		Version:       version,
		Schema:        make(map[string]interface{}),
		EventSchema:   make(map[string]interface{}),
		EntitySchemas: make(map[string]map[string]interface{}),
		LoadedAt:      time.Now(),
	}

	// Load event schema
	eventDir := filepath.Join(versionDir, "event")
	eventSchemaPath := filepath.Join(eventDir, "event.json")
	if data, err := os.ReadFile(eventSchemaPath); err == nil {
		if err := json.Unmarshal(data, &cached.EventSchema); err != nil {
			return nil, fmt.Errorf("failed to parse event schema: %w", err)
		}
	}

	// Load entity schemas
	entityDir := filepath.Join(versionDir, "entity")
	if entries, err := os.ReadDir(entityDir); err == nil {
		for _, entry := range entries {
			if entry.IsDir() || filepath.Ext(entry.Name()) != ".json" {
				continue
			}

			entityPath := filepath.Join(entityDir, entry.Name())
			data, err := os.ReadFile(entityPath)
			if err != nil {
				sc.logger.Warn("Failed to read entity schema",
					zap.String("path", entityPath),
					zap.Error(err))
				continue
			}

			var entitySchema map[string]interface{}
			if err := json.Unmarshal(data, &entitySchema); err != nil {
				sc.logger.Warn("Failed to parse entity schema",
					zap.String("path", entityPath),
					zap.Error(err))
				continue
			}

			entityName := entry.Name()[:len(entry.Name())-5] // Remove .json extension
			cached.EntitySchemas[entityName] = entitySchema
		}
	}

	sc.logger.Info("Loaded schema version",
		zap.String("version", version),
		zap.Int("entity_count", len(cached.EntitySchemas)))

	return cached, nil
}

func (sc *SchemaCache) GetVersions(schemasDir string) ([]string, error) {
	// Check if schemasDir contains a "schemas" subdirectory (git repo structure)
	schemasSubDir := filepath.Join(schemasDir, "schemas")
	if _, err := os.Stat(schemasSubDir); err == nil {
		schemasDir = schemasSubDir
	}
	
	entries, err := os.ReadDir(schemasDir)
	if err != nil {
		return nil, fmt.Errorf("failed to read schemas directory: %w", err)
	}

	var versions []string
	for _, entry := range entries {
		if entry.IsDir() && entry.Name() != ".git" {
			versions = append(versions, entry.Name())
		}
	}

	return versions, nil
}

func (sc *SchemaCache) Invalidate(version string) {
	sc.mu.Lock()
	defer sc.mu.Unlock()
	delete(sc.cache, version)
}

func (sc *SchemaCache) InvalidateAll() {
	sc.mu.Lock()
	defer sc.mu.Unlock()
	sc.cache = make(map[string]*CachedSchema)
}

