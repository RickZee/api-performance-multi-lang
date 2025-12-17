package grpcweb

import (
	"encoding/base64"
	"fmt"
	"io"
	"strings"

	"google.golang.org/protobuf/proto"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const (
	// ContentTypeProto is the content type for binary protobuf gRPC-Web
	ContentTypeProto = "application/grpc-web+proto"
	// ContentTypeText is the content type for text (base64) protobuf gRPC-Web
	ContentTypeText = "application/grpc-web-text"
)

// DecodeRequest decodes a gRPC-Web request body
// gRPC-Web can be either binary (application/grpc-web+proto) or base64-encoded (application/grpc-web-text)
func DecodeRequest(contentType string, body []byte) ([]byte, error) {
	if strings.Contains(contentType, ContentTypeText) {
		// Base64 decode
		decoded := make([]byte, base64.StdEncoding.DecodedLen(len(body)))
		n, err := base64.StdEncoding.Decode(decoded, body)
		if err != nil {
			return nil, fmt.Errorf("failed to decode base64 gRPC-Web request: %w", err)
		}
		return decoded[:n], nil
	} else if strings.Contains(contentType, ContentTypeProto) {
		// Already binary
		return body, nil
	}
	return nil, fmt.Errorf("unsupported content type: %s", contentType)
}

// EncodeResponse encodes a protobuf message for gRPC-Web response
// Returns the encoded body and appropriate content type
func EncodeResponse(message proto.Message, useText bool) ([]byte, string, error) {
	// Marshal protobuf
	data, err := proto.Marshal(message)
	if err != nil {
		return nil, "", fmt.Errorf("failed to marshal protobuf: %w", err)
	}

	// Add gRPC-Web frame (5-byte header: 1 byte flags + 4 bytes length)
	frame := make([]byte, 5+len(data))
	frame[0] = 0x00 // Flags: no compression
	// Length in big-endian
	frame[1] = byte(len(data) >> 24)
	frame[2] = byte(len(data) >> 16)
	frame[3] = byte(len(data) >> 8)
	frame[4] = byte(len(data))
	copy(frame[5:], data)

	if useText {
		// Base64 encode
		encoded := make([]byte, base64.StdEncoding.EncodedLen(len(frame)))
		base64.StdEncoding.Encode(encoded, frame)
		return encoded, ContentTypeText, nil
	}

	return frame, ContentTypeProto, nil
}

// EncodeError encodes a gRPC error status for gRPC-Web response
// Returns the error trailer frame and appropriate content type
func EncodeError(err error, useText bool) ([]byte, string, int) {
	st, ok := status.FromError(err)
	if !ok {
		st = status.New(codes.Internal, err.Error())
	}

	// Create gRPC-Web error trailer
	// Format: grpc-status: <code>\r\ngrpc-message: <message>\r\n
	errorTrailer := fmt.Sprintf("grpc-status: %d\r\ngrpc-message: %s\r\n", int(st.Code()), st.Message())
	
	if useText {
		// Base64 encode the trailer
		encoded := make([]byte, base64.StdEncoding.EncodedLen(len(errorTrailer)))
		base64.StdEncoding.Encode(encoded, []byte(errorTrailer))
		return encoded, ContentTypeText, int(st.Code())
	}

	return []byte(errorTrailer), ContentTypeProto, int(st.Code())
}

// ParseMethodPath extracts service and method from gRPC-Web path
// Format: /package.Service/Method
func ParseMethodPath(path string) (service, method string, err error) {
	// Remove leading slash
	path = strings.TrimPrefix(path, "/")
	
	// Split by slash
	parts := strings.Split(path, "/")
	if len(parts) != 2 {
		return "", "", fmt.Errorf("invalid gRPC-Web path format: %s", path)
	}

	// Extract service and method
	serviceMethod := parts[0]
	method = parts[1]

	// Service might be package.Service, extract just the service name
	serviceParts := strings.Split(serviceMethod, ".")
	service = serviceParts[len(serviceParts)-1]

	return service, method, nil
}

// ReadGRPCWebFrame reads a gRPC-Web frame from the data
// Returns the message data and remaining data
func ReadGRPCWebFrame(data []byte) ([]byte, []byte, error) {
	if len(data) < 5 {
		return nil, data, io.ErrUnexpectedEOF
	}

	// Read flags (1 byte) and length (4 bytes, big-endian)
	flags := data[0]
	length := int(data[1])<<24 | int(data[2])<<16 | int(data[3])<<8 | int(data[4])

	if flags != 0x00 {
		return nil, nil, fmt.Errorf("compression not supported, flags: %d", flags)
	}

	if len(data) < 5+length {
		return nil, data, io.ErrUnexpectedEOF
	}

	message := data[5 : 5+length]
	remaining := data[5+length:]

	return message, remaining, nil
}
