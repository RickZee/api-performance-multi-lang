package errors

import (
	"fmt"
	"net/http"
)

// AppError represents an application error
type AppError struct {
	Message    string
	StatusCode int
	Err        error
}

func (e *AppError) Error() string {
	if e.Err != nil {
		return fmt.Sprintf("%s: %v", e.Message, e.Err)
	}
	return e.Message
}

func (e *AppError) Unwrap() error {
	return e.Err
}

// NewDatabaseError creates a database error
func NewDatabaseError(err error) *AppError {
	return &AppError{
		Message:    "Database error",
		StatusCode: http.StatusInternalServerError,
		Err:        err,
	}
}

// NewValidationError creates a validation error
func NewValidationError(message string) *AppError {
	return &AppError{
		Message:    message,
		StatusCode: http.StatusUnprocessableEntity,
	}
}

// NewNotFoundError creates a not found error
func NewNotFoundError(message string) *AppError {
	return &AppError{
		Message:    message,
		StatusCode: http.StatusNotFound,
	}
}

// NewInternalError creates an internal server error
func NewInternalError(err error) *AppError {
	return &AppError{
		Message:    "Internal server error",
		StatusCode: http.StatusInternalServerError,
		Err:        err,
	}
}

// NewJSONError creates a JSON parsing error
func NewJSONError(err error) *AppError {
	return &AppError{
		Message:    "Invalid JSON",
		StatusCode: http.StatusBadRequest,
		Err:        err,
	}
}
