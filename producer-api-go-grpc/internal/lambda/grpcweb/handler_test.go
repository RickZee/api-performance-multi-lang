package grpcweb

import (
	"encoding/base64"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func TestDecodeRequest_Text(t *testing.T) {
	original := []byte("test data")
	encoded := base64.StdEncoding.EncodeToString(original)

	decoded, err := DecodeRequest(ContentTypeText, []byte(encoded))
	require.NoError(t, err)
	assert.Equal(t, original, decoded)
}

func TestDecodeRequest_Proto(t *testing.T) {
	original := []byte("test data")
	decoded, err := DecodeRequest(ContentTypeProto, original)
	require.NoError(t, err)
	assert.Equal(t, original, decoded)
}

func TestEncodeResponse_Text(t *testing.T) {
	// Create a simple test message
	// In a real test, you'd use an actual protobuf message
	testData := []byte("test message")
	
	// We can't easily test with a real proto.Message without importing the actual proto
	// This is a placeholder test structure
	t.Skip("Skipping - requires actual protobuf message type")
}

func TestEncodeError(t *testing.T) {
	err := status.Error(codes.InvalidArgument, "test error")
	
	body, contentType, code := EncodeError(err, true)
	
	assert.Equal(t, ContentTypeText, contentType)
	assert.Equal(t, int(codes.InvalidArgument), code)
	assert.NotEmpty(t, body)
}

func TestParseMethodPath(t *testing.T) {
	tests := []struct {
		name        string
		path        string
		expectService string
		expectMethod  string
		expectError   bool
	}{
		{
			name:          "valid path",
			path:          "/com.example.grpc.EventService/ProcessEvent",
			expectService: "EventService",
			expectMethod:  "ProcessEvent",
			expectError:   false,
		},
		{
			name:          "path without package",
			path:          "/EventService/HealthCheck",
			expectService: "EventService",
			expectMethod:  "HealthCheck",
			expectError:   false,
		},
		{
			name:        "invalid path - no slash",
			path:        "invalid",
			expectError: true,
		},
		{
			name:        "invalid path - too many parts",
			path:        "/a/b/c",
			expectError: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			service, method, err := ParseMethodPath(tt.path)
			
			if tt.expectError {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
				assert.Equal(t, tt.expectService, service)
				assert.Equal(t, tt.expectMethod, method)
			}
		})
	}
}

func TestReadGRPCWebFrame(t *testing.T) {
	message := []byte("test message")
	frame := make([]byte, 5+len(message))
	frame[0] = 0x00 // Flags
	frame[1] = byte(len(message) >> 24)
	frame[2] = byte(len(message) >> 16)
	frame[3] = byte(len(message) >> 8)
	frame[4] = byte(len(message))
	copy(frame[5:], message)

	decoded, remaining, err := ReadGRPCWebFrame(frame)
	require.NoError(t, err)
	assert.Equal(t, message, decoded)
	assert.Empty(t, remaining)
}

func TestReadGRPCWebFrame_TooShort(t *testing.T) {
	shortFrame := []byte{0x00, 0x00}
	_, _, err := ReadGRPCWebFrame(shortFrame)
	assert.Error(t, err)
}
