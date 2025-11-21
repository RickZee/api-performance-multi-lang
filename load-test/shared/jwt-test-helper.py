#!/usr/bin/env python3
"""
JWT Test Helper
Generates test JWT tokens for performance testing
"""

import json
import sys
import time
import jwt
from datetime import datetime, timedelta


# Test signing key (NOT for production use)
TEST_SIGNING_KEY = 'test-signing-key-for-jwt-tokens-not-for-production-use'


def generate_test_token(
    user_id: str = 'test-user',
    roles: list = None,
    expires_in_seconds: int = 3600,
    issuer: str = 'test-issuer',
    audience: str = 'test-audience'
) -> str:
    """Generate a test JWT token"""
    if roles is None:
        roles = ['user']
    
    now = datetime.utcnow()
    payload = {
        'sub': user_id,
        'iss': issuer,
        'aud': audience,
        'exp': int((now + timedelta(seconds=expires_in_seconds)).timestamp()),
        'iat': int(now.timestamp()),
        'roles': roles
    }
    
    token = jwt.encode(payload, TEST_SIGNING_KEY, algorithm='HS256')
    return token


def generate_expired_token() -> str:
    """Generate an expired JWT token for testing rejection paths"""
    return generate_test_token(expires_in_seconds=-3600)


def generate_invalid_token() -> str:
    """Generate an invalid JWT token (wrong signature)"""
    payload = {
        'sub': 'test-user',
        'exp': int((datetime.utcnow() + timedelta(seconds=3600)).timestamp())
    }
    # Use wrong key to create invalid signature
    return jwt.encode(payload, 'wrong-key', algorithm='HS256')


def main():
    """CLI interface for generating tokens"""
    if len(sys.argv) < 2:
        print("Usage: jwt-test-helper.py <command> [args...]")
        print("Commands:")
        print("  generate [user_id] [roles...] - Generate a valid token")
        print("  expired - Generate an expired token")
        print("  invalid - Generate an invalid token")
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == 'generate':
        user_id = sys.argv[2] if len(sys.argv) > 2 else 'test-user'
        roles = sys.argv[3:] if len(sys.argv) > 3 else ['user']
        token = generate_test_token(user_id=user_id, roles=roles)
        print(token)
    elif command == 'expired':
        token = generate_expired_token()
        print(token)
    elif command == 'invalid':
        token = generate_invalid_token()
        print(token)
    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()

