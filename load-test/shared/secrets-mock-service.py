#!/usr/bin/env python3
"""
Mock Secrets Service
Simulates a remote secrets store (like AWS Secrets Manager) for testing
"""

import json
import sys
import time
import random
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import os


# Mock secrets storage
SECRETS_STORE = {
    'database_url': 'postgresql://postgres:password@postgres-large:5432/car_entities',
    'database_password': 'password',
    'jwt_signing_key': 'test-signing-key-for-jwt-tokens-not-for-production-use',
    'api_key': 'test-api-key-12345'
}

# Configuration
DELAY_MS = int(os.getenv('SECRETS_SERVICE_DELAY_MS', '0'))  # Artificial delay in milliseconds
FAILURE_RATE = float(os.getenv('SECRETS_SERVICE_FAILURE_RATE', '0.0'))  # Failure rate (0.0 to 1.0)
TIMEOUT_RATE = float(os.getenv('SECRETS_SERVICE_TIMEOUT_RATE', '0.0'))  # Timeout rate (0.0 to 1.0)


class SecretsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        """Handle GET requests for secret retrieval"""
        parsed_path = urlparse(self.path)
        path = parsed_path.path
        
        # Simulate delay
        if DELAY_MS > 0:
            time.sleep(DELAY_MS / 1000.0)
        
        # Simulate failures
        if random.random() < FAILURE_RATE:
            self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'error': 'Internal server error'}).encode())
            return
        
        # Simulate timeouts
        if random.random() < TIMEOUT_RATE:
            time.sleep(30)  # Simulate timeout
            return
        
        if path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'healthy'}).encode())
        elif path.startswith('/secrets/'):
            secret_name = path.split('/secrets/')[1]
            if secret_name in SECRETS_STORE:
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({
                    'name': secret_name,
                    'value': SECRETS_STORE[secret_name]
                }).encode())
            else:
                self.send_response(404)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'error': 'Secret not found'}).encode())
        else:
            self.send_response(404)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'error': 'Not found'}).encode())
    
    def log_message(self, format, *args):
        # Suppress default logging
        pass


def run_server(port=8080):
    """Run the mock secrets service"""
    server = HTTPServer(('0.0.0.0', port), SecretsHandler)
    print(f"Mock secrets service running on port {port}", file=sys.stderr)
    print(f"Configuration: delay={DELAY_MS}ms, failure_rate={FAILURE_RATE}, timeout_rate={TIMEOUT_RATE}", file=sys.stderr)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down secrets service...", file=sys.stderr)
        server.shutdown()


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    run_server(port)

