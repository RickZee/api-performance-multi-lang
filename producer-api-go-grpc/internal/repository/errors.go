package repository

import "fmt"

// DuplicateEventError is raised when attempting to create an event with an existing ID
type DuplicateEventError struct {
	EventID string
	Message string
}

func (e *DuplicateEventError) Error() string {
	if e.Message != "" {
		return e.Message
	}
	return fmt.Sprintf("Event with ID '%s' already exists", e.EventID)
}

func NewDuplicateEventError(eventID string, message string) *DuplicateEventError {
	if message == "" {
		message = fmt.Sprintf("Event with ID '%s' already exists", eventID)
	}
	return &DuplicateEventError{
		EventID: eventID,
		Message: message,
	}
}
