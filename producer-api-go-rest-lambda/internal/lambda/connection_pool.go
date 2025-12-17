package lambda

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
)

var (
	poolOnce sync.Once
	pool     *pgxpool.Pool
	poolErr  error
)

// GetConnectionPool returns a singleton database connection pool for Lambda
// The pool is initialized once and reused across Lambda invocations
func GetConnectionPool(databaseURL string, logger *zap.Logger) (*pgxpool.Pool, error) {
	poolOnce.Do(func() {
		config, err := pgxpool.ParseConfig(databaseURL)
		if err != nil {
			poolErr = fmt.Errorf("failed to parse database URL: %w", err)
			return
		}

		// Lambda-optimized pool settings
		// Reduced pool size - RDS Proxy handles connection pooling
		config.MaxConns = 2
		config.MinConns = 1
		// Longer idle timeout since Lambda containers are reused
		config.MaxConnIdleTime = 0 // Keep connections alive as long as possible
		config.MaxConnLifetime = 0 // No max lifetime for Lambda reuse
		// Health check settings - use a reasonable interval (30s) instead of 0
		// Setting to 0 causes panic in newer pgx versions
		config.HealthCheckPeriod = 30 * time.Second

		pool, poolErr = pgxpool.NewWithConfig(context.Background(), config)
		if poolErr != nil {
			poolErr = fmt.Errorf("failed to create connection pool: %w", poolErr)
			return
		}

		// Test the connection
		if err := pool.Ping(context.Background()); err != nil {
			poolErr = fmt.Errorf("failed to ping database: %w", err)
			pool.Close()
			pool = nil
			return
		}

		if logger != nil {
			logger.Info("Lambda connection pool initialized successfully",
				zap.Int("max_connections", int(config.MaxConns)),
				zap.Int("min_connections", int(config.MinConns)),
			)
		}
	})

	return pool, poolErr
}

// CloseConnectionPool closes the connection pool (useful for testing)
func CloseConnectionPool() {
	if pool != nil {
		pool.Close()
		pool = nil
		// Reset once to allow re-initialization in tests
		poolOnce = sync.Once{}
	}
}
