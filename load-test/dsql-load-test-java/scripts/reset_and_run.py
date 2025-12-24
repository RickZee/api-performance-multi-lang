#!/usr/bin/env python3
"""
Reset test results and run the entire test suite.
Python replacement for reset_and_run.sh for consistency.
"""

import sys
import shutil
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

# Import run_test_suite main function
import importlib.util
run_test_suite_path = Path(__file__).parent / 'run_test_suite.py'
spec = importlib.util.spec_from_file_location("run_test_suite", run_test_suite_path)
run_test_suite_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(run_test_suite_module)
run_test_suite = run_test_suite_module.main


def reset_results():
    """Clear all previous test results."""
    script_dir = Path(__file__).parent.parent
    results_dir = script_dir / 'results'
    
    if results_dir.exists():
        print("Removing old results...")
        for item in results_dir.iterdir():
            if item.is_dir():
                shutil.rmtree(item)
            else:
                item.unlink()
        print("✅ Results directory cleared")
    else:
        results_dir.mkdir(parents=True, exist_ok=True)
        print("✅ Results directory created")
    
    # Remove latest symlink if exists
    latest_link = results_dir / 'latest'
    if latest_link.exists() or latest_link.is_symlink():
        latest_link.unlink()


def main():
    print("=" * 80)
    print("Reset and Run Full Test Suite")
    print("=" * 80)
    print()
    
    # Ask for confirmation
    try:
        response = input("This will clear all previous test results. Continue? (y/N): ").strip().lower()
        if response not in ['y', 'yes']:
            print("Cancelled.")
            return
    except KeyboardInterrupt:
        print("\nCancelled.")
        return
    
    # Clear results
    print()
    print("=== Clearing Previous Results ===")
    reset_results()
    print()
    
    # Run the test suite
    print("=== Starting Full Test Suite ===")
    print("This will run all 32 tests (estimated 2-4 hours)")
    print()
    print("To monitor progress in another terminal, run:")
    print("  python3 scripts/monitor_tests.py")
    print()
    
    try:
        response = input("Start now? (Y/n): ").strip().lower()
        if response in ['n', 'no']:
            print("Cancelled.")
            return
    except KeyboardInterrupt:
        print("\nCancelled.")
        return
    
    print()
    print("Starting test suite...")
    print()
    
    # Run test suite
    try:
        run_test_suite()
    except KeyboardInterrupt:
        print("\n\nTest suite interrupted by user")
        sys.exit(130)
    except SystemExit as e:
        sys.exit(e.code if e.code else 0)
    except Exception as e:
        print(f"\nError: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    
    print()
    print("=" * 80)
    print("Test Suite Complete")
    print("=" * 80)
    print()
    print("Results are in: results/latest")
    print()
    print("To analyze results:")
    print("  python3 scripts/analyze_results.py")
    print()


if __name__ == '__main__':
    main()

