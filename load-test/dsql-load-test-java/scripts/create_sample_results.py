#!/usr/bin/env python3
"""
Create sample test results for demonstration of metrics and charts.
"""

import json
import sys
from pathlib import Path
from datetime import datetime

sys.path.insert(0, str(Path(__file__).parent.parent))


def create_sample_results(output_dir: Path):
    """Create sample test result files."""
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Sample test configurations
    tests = [
        {
            'test_id': 'test-001-minimal_scenario1-threads2-loops2-count2-payloaddefault',
            'scenario': 1,
            'threads': 2,
            'iterations': 2,
            'count': 2,
            'throughput': 1500,
            'p95_latency': 45,
            'errors': 0
        },
        {
            'test_id': 'test-002-minimal_scenario2-threads2-loops2-count2-payloaddefault',
            'scenario': 2,
            'threads': 2,
            'iterations': 2,
            'count': 2,
            'batch_size': 2,
            'throughput': 3200,
            'p95_latency': 38,
            'errors': 0
        },
        {
            'test_id': 'test-003-scenario1_thread_scaling-threads10-loops20-count1-payloaddefault',
            'scenario': 1,
            'threads': 10,
            'iterations': 20,
            'count': 1,
            'throughput': 8500,
            'p95_latency': 52,
            'errors': 2
        },
        {
            'test_id': 'test-004-scenario1_thread_scaling-threads25-loops20-count1-payloaddefault',
            'scenario': 1,
            'threads': 25,
            'iterations': 20,
            'count': 1,
            'throughput': 18200,
            'p95_latency': 68,
            'errors': 5
        },
        {
            'test_id': 'test-005-scenario2_batch_impact-threads10-loops20-count10-payloaddefault',
            'scenario': 2,
            'threads': 10,
            'iterations': 20,
            'count': 10,
            'batch_size': 10,
            'throughput': 12500,
            'p95_latency': 42,
            'errors': 1
        },
        {
            'test_id': 'test-006-scenario2_batch_impact-threads10-loops20-count25-payloaddefault',
            'scenario': 2,
            'threads': 10,
            'iterations': 20,
            'count': 25,
            'batch_size': 25,
            'throughput': 28500,
            'p95_latency': 35,
            'errors': 0
        },
    ]
    
    for test in tests:
        total_ops = test['threads'] * test['iterations'] * test['count']
        success = total_ops - test['errors']
        
        result_data = {
            'test_id': test['test_id'],
            'configuration': {
                'scenario': test['scenario'],
                'threads': test['threads'],
                'iterations': test['iterations'],
                'count': test['count'],
                'batch_size': test.get('batch_size'),
                'payload_size': 'default',
                'event_type': 'CarCreated'
            },
            'results': {
                f"scenario_{test['scenario']}": {
                    'total_success': success,
                    'total_errors': test['errors'],
                    'duration_ms': int((total_ops / test['throughput']) * 1000),
                    'throughput_inserts_per_sec': test['throughput'],
                    'avg_inserts_per_sec': test['throughput'],
                    'expected_rows': total_ops,
                    'actual_rows': success,
                    'latency_stats': {
                        'min': int(test['p95_latency'] * 0.3),
                        'max': int(test['p95_latency'] * 1.5),
                        'avg': int(test['p95_latency'] * 0.7),
                        'p50': int(test['p95_latency'] * 0.6),
                        'p95': test['p95_latency'],
                        'p99': int(test['p95_latency'] * 1.2)
                    },
                    'pool_metrics': {
                        'pool_size': min(test['threads'] * 2, 50),
                        'active_connections': test['threads']
                    }
                }
            },
            'timestamp': datetime.now().isoformat()
        }
        
        output_file = output_dir / f"{test['test_id']}.json"
        with open(output_file, 'w') as f:
            json.dump(result_data, f, indent=2)
        
        print(f"Created: {output_file.name}")
    
    print(f"\n✓ Created {len(tests)} sample test results in {output_dir}")


if __name__ == '__main__':
    script_dir = Path(__file__).parent.parent
    sample_dir = script_dir / 'results' / 'sample-minimal'
    create_sample_results(sample_dir)
    print(f"\nRun metrics generation:")
    print(f"  python3 scripts/generate_detailed_metrics.py {sample_dir}")

