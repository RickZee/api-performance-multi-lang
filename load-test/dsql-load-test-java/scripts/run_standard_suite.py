#!/usr/bin/env python3
"""
Run the standard test suite (excluding extreme scaling tests).
Convenience script that automatically excludes extreme scenarios.
"""

import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from scripts.run_test_suite import main

# Standard test groups (excluding extreme scaling)
STANDARD_GROUPS = [
    'scenario1_thread_scaling',
    'scenario1_loop_impact',
    'scenario1_payload_impact',
    'scenario1_super_heavy_1',
    'scenario1_super_heavy_2',
    'scenario2_thread_scaling',
    'scenario2_batch_impact',
    'scenario2_payload_impact',
    'scenario2_super_heavy_1',
    'scenario2_super_heavy_2',
]

if __name__ == '__main__':
    # Override sys.argv to pass groups
    original_argv = sys.argv.copy()
    sys.argv = [sys.argv[0], '--groups'] + STANDARD_GROUPS + original_argv[1:]
    
    print("=" * 80)
    print("Running Standard Test Suite (Excluding Extreme Scaling)")
    print("=" * 80)
    print(f"Test Groups: {len(STANDARD_GROUPS)}")
    print(f"Excluded: scenario2_extreme_scaling_1-4 (4 extreme tests)")
    print()
    
    main()

