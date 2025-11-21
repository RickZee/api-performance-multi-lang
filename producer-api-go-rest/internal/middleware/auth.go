package middleware

import (
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// JWTAuthMiddleware is a placeholder for JWT authentication middleware
// When AUTH_ENABLED=true, this middleware validates JWT tokens in the Authorization header
// Currently returns success for all requests (to be implemented)
func JWTAuthMiddleware(logger *zap.Logger, enabled bool) gin.HandlerFunc {
	if !enabled {
		// Auth disabled - pass through
		return func(c *gin.Context) {
			c.Next()
		}
	}

	return func(c *gin.Context) {
		start := time.Now()
		
		// Extract token from Authorization header
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error":  "Missing Authorization header",
				"status": http.StatusUnauthorized,
			})
			c.Abort()
			return
		}

		// Check Bearer token format
		parts := strings.Split(authHeader, " ")
		if len(parts) != 2 || parts[0] != "Bearer" {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error":  "Invalid Authorization header format",
				"status": http.StatusUnauthorized,
			})
			c.Abort()
			return
		}

		token := parts[1]
		
		// TODO: Implement JWT validation
		// For now, just check that token exists (placeholder)
		if token == "" {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error":  "Missing token",
				"status": http.StatusUnauthorized,
			})
			c.Abort()
			return
		}

		// TODO: Validate JWT signature, expiration, claims
		// For now, accept any non-empty token
		
		authDuration := time.Since(start)
		logger.Debug("JWT auth validated",
			zap.String("path", c.Request.URL.Path),
			zap.Duration("auth_duration_ms", authDuration),
		)

		// Store token in context for potential use in handlers
		c.Set("jwt_token", token)
		
		c.Next()
	}
}

