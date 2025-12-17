"""Configuration management for test runner."""

from dataclasses import dataclass
from typing import List, Optional, Dict, Tuple
from enum import Enum


class TestMode(str, Enum):
    """Test mode enumeration."""
    SMOKE = "smoke"
    FULL = "full"
    SATURATION = "saturation"


@dataclass
class APIConfig:
    """Configuration for a single API."""
    name: str
    test_file: str
    port: int
    protocol: str  # "http" or "grpc"
    profile: str
    docker_host: str
    proto_file: Optional[str] = None
    service_name: Optional[str] = None
    method_name: Optional[str] = None
    health_check_port: Optional[int] = None
    is_lambda: bool = False  # True if this is a Lambda API (uses SAM Local instead of Docker)


@dataclass
class TestConfig:
    """Test configuration."""
    test_mode: TestMode
    api_names: List[str]  # Empty list means all APIs
    payload_sizes: List[str]  # Empty list means default only
    base_dir: str
    results_dir: str
    skip_rebuild: bool = False
    skip_healthcheck: bool = False
    verbose: bool = False


class ConfigManager:
    """Manages API and test configurations."""
    
    # All available APIs
    ALL_APIS = [
        "producer-api-java-rest",
        "producer-api-java-grpc",
        "producer-api-rust-rest",
        "producer-api-rust-grpc",
        "producer-api-go-rest",
        "producer-api-go-grpc",
        "producer-api-go-rest-lambda",
        "producer-api-go-grpc-lambda",
        "producer-api-python-rest-lambda-pg",
    ]
    
    @staticmethod
    def get_api_config(api_name: str) -> Optional[APIConfig]:
        """Get configuration for a specific API."""
        configs = {
            "producer-api-java-rest": APIConfig(
                name="producer-api-java-rest",
                test_file="rest-api-test.js",
                port=8081,
                protocol="http",
                profile="producer",
                docker_host="producer-api-java-rest",
                health_check_port=9081,
            ),
            "producer-api-java-grpc": APIConfig(
                name="producer-api-java-grpc",
                test_file="grpc-api-test.js",
                port=9090,
                protocol="grpc",
                profile="producer-grpc",
                docker_host="producer-api-java-grpc",
                proto_file="/k6/proto/java-grpc/event_service.proto",
                service_name="com.example.grpc.EventService",
                method_name="ProcessEvent",
                health_check_port=9090,
            ),
            "producer-api-rust-rest": APIConfig(
                name="producer-api-rust-rest",
                test_file="rest-api-test.js",
                port=8081,
                protocol="http",
                profile="producer-rust",
                docker_host="producer-api-rust-rest",
                health_check_port=9082,
            ),
            "producer-api-rust-grpc": APIConfig(
                name="producer-api-rust-grpc",
                test_file="grpc-api-test.js",
                port=9090,
                protocol="grpc",
                profile="producer-rust-grpc",
                docker_host="producer-api-rust-grpc",
                proto_file="/k6/proto/rust-grpc/event_service.proto",
                service_name="com.example.grpc.EventService",
                method_name="ProcessEvent",
                health_check_port=9091,
            ),
            "producer-api-go-rest": APIConfig(
                name="producer-api-go-rest",
                test_file="rest-api-test.js",
                port=9083,
                protocol="http",
                profile="producer-go",
                docker_host="producer-api-go-rest",
                health_check_port=9083,
            ),
            "producer-api-go-grpc": APIConfig(
                name="producer-api-go-grpc",
                test_file="grpc-api-test.js",
                port=9092,
                protocol="grpc",
                profile="producer-go-grpc",
                docker_host="producer-api-go-grpc",
                proto_file="/k6/proto/go-grpc/event_service.proto",
                service_name="com.example.grpc.EventService",
                method_name="ProcessEvent",
                health_check_port=9092,
            ),
            "producer-api-go-rest-lambda": APIConfig(
                name="producer-api-go-rest-lambda",
                test_file="lambda-rest-api-test.js",
                port=9084,
                protocol="http",
                profile="lambda",  # Not used for Lambda, but kept for consistency
                docker_host="localhost",  # Lambda APIs run on localhost via SAM Local
                health_check_port=9084,
                is_lambda=True,
            ),
            "producer-api-go-grpc-lambda": APIConfig(
                name="producer-api-go-grpc-lambda",
                test_file="lambda-grpc-api-test.js",
                port=9085,
                protocol="grpc",
                profile="lambda",  # Not used for Lambda, but kept for consistency
                docker_host="localhost",  # Lambda APIs run on localhost via SAM Local
                service_name="com.example.grpc.EventService",
                method_name="ProcessEvent",
                health_check_port=9085,
                is_lambda=True,
            ),
            "producer-api-python-rest-lambda-pg": APIConfig(
                name="producer-api-python-rest-lambda-pg",
                test_file="lambda-rest-api-test.js",
                port=9088,
                protocol="http",
                profile="lambda",  # Not used for Lambda, but kept for consistency
                docker_host="localhost",  # Lambda APIs run on localhost via SAM Local
                health_check_port=9088,
                is_lambda=True,
            ),
        }
        return configs.get(api_name)
    
    @staticmethod
    def get_phase_info(test_mode: TestMode) -> List[Dict]:
        """Get phase information for a test mode."""
        if test_mode == TestMode.SMOKE:
            return [{'num': 1, 'name': 'Smoke Test', 'duration': 30, 'vus': 1}]
        elif test_mode == TestMode.FULL:
            return [
                {'num': 1, 'name': 'Baseline', 'duration': 120, 'vus': 10},
                {'num': 2, 'name': 'Mid-load', 'duration': 120, 'vus': 50},
                {'num': 3, 'name': 'High-load', 'duration': 120, 'vus': 100},
                {'num': 4, 'name': 'Higher-load', 'duration': 300, 'vus': 200},
            ]
        elif test_mode == TestMode.SATURATION:
            return [
                {'num': 1, 'name': 'Baseline', 'duration': 120, 'vus': 10},
                {'num': 2, 'name': 'Mid-load', 'duration': 120, 'vus': 50},
                {'num': 3, 'name': 'High-load', 'duration': 120, 'vus': 100},
                {'num': 4, 'name': 'Very High', 'duration': 120, 'vus': 200},
                {'num': 5, 'name': 'Extreme', 'duration': 120, 'vus': 500},
                {'num': 6, 'name': 'Maximum', 'duration': 120, 'vus': 1000},
                {'num': 7, 'name': 'Saturation', 'duration': 120, 'vus': 2000},
            ]
        return []
    
    @staticmethod
    def get_test_duration(test_mode: TestMode) -> int:
        """Get expected test duration in seconds."""
        phases = ConfigManager.get_phase_info(test_mode)
        return sum(p['duration'] for p in phases)
    
    @staticmethod
    def get_payload_sizes(test_mode: TestMode, specified: Optional[List[str]] = None) -> List[str]:
        """Get list of payload sizes to test."""
        if specified:
            return specified
        # For all test modes, test all payload sizes
        return ["400b", "4k", "8k", "32k", "64k"]
    
    @staticmethod
    def validate_api_name(api_name: str) -> bool:
        """Validate that an API name is valid."""
        return api_name in ConfigManager.ALL_APIS
