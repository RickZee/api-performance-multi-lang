#!/usr/bin/env python3
"""
Python Test Runner with Rich UI
Orchestrates k6 performance tests with beautiful console visualization.
"""

import sys
import argparse
from pathlib import Path
from rich.console import Console
from rich import print as rprint

# Add current directory to path for imports
script_dir = Path(__file__).parent
sys.path.insert(0, str(script_dir))

# Import test runner modules
from test_runner.config import TestConfig, TestMode, ConfigManager
from test_runner.runner import TestRunner


def parse_arguments():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Run performance tests with Rich UI",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run smoke tests for all APIs
  python run-tests.py smoke

  # Run full tests for a specific API
  python run-tests.py full --api producer-api-go-rest

  # Run saturation tests with specific payload size
  python run-tests.py saturation --payload-size 4k

  # Run tests for multiple APIs
  python run-tests.py full --api producer-api-go-rest --api producer-api-rust-rest
        """
    )
    
    parser.add_argument(
        "test_mode",
        choices=["smoke", "full", "saturation"],
        help="Test mode: smoke (quick), full (baseline), or saturation (maximum)"
    )
    
    parser.add_argument(
        "--api",
        action="append",
        dest="apis",
        help="API to test (can be specified multiple times). If not specified, all APIs are tested."
    )
    
    parser.add_argument(
        "--payload-size",
        action="append",
        dest="payload_sizes",
        help="Payload size to test (default, 4k, 8k, 32k, 64k). Can be specified multiple times."
    )
    
    parser.add_argument(
        "--skip-rebuild",
        action="store_true",
        help="Skip rebuilding Docker images (use existing images)"
    )
    
    parser.add_argument(
        "--skip-healthcheck",
        action="store_true",
        help="Skip healthcheck cycle before tests"
    )
    
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Verbose output"
    )
    
    parser.add_argument(
        "--base-dir",
        type=str,
        default=None,
        help="Base directory of the project (default: auto-detect)"
    )
    
    return parser.parse_args()


def main():
    """Main entry point."""
    args = parse_arguments()
    console = Console()
    
    # Determine base directory
    if args.base_dir:
        base_dir = Path(args.base_dir)
    else:
        # Auto-detect: go up from load-test/shared to project root
        base_dir = Path(__file__).parent.parent.parent
    
    if not base_dir.exists():
        console.print(f"[red]Error: Base directory does not exist: {base_dir}[/red]")
        return 1
    
    # Validate API names if specified
    api_names = args.apis if args.apis else []
    for api_name in api_names:
        if not ConfigManager.validate_api_name(api_name):
            console.print(f"[red]Error: Invalid API name: {api_name}[/red]")
            console.print(f"[yellow]Valid APIs: {', '.join(ConfigManager.ALL_APIS)}[/yellow]")
            return 1
    
    # Create test configuration
    test_mode = TestMode(args.test_mode)
    payload_sizes = args.payload_sizes if args.payload_sizes else None
    
    config = TestConfig(
        test_mode=test_mode,
        api_names=api_names,
        payload_sizes=payload_sizes,
        base_dir=str(base_dir),
        results_dir=str(base_dir / "load-test" / "results" / "throughput-sequential"),
        skip_rebuild=args.skip_rebuild,
        skip_healthcheck=args.skip_healthcheck,
        verbose=args.verbose,
    )
    
    # Check if Rich is available
    try:
        import rich
    except ImportError:
        console.print("[red]Error: Rich library is not installed.[/red]")
        console.print("[yellow]Install it with: pip install rich[/yellow]")
        return 1
    
    # Force console to be interactive for Rich UI
    # Create a new console with force_terminal to ensure Rich UI works
    from rich.console import Console as RichConsole
    console = RichConsole(force_terminal=True, force_interactive=True)
    
    # Check if running in interactive terminal
    if not console.is_terminal:
        console.print("[yellow]Warning: Not running in interactive terminal. UI may be limited.[/yellow]")
    else:
        console.print("[green]Rich UI enabled - you'll see a live dashboard during test execution[/green]")
    
    # Create and run test runner
    try:
        runner = TestRunner(config, console)
        exit_code = runner.run()
        return exit_code
    except KeyboardInterrupt:
        console.print("\n[yellow]Test execution interrupted by user[/yellow]")
        return 130
    except Exception as e:
        console.print(f"[red]Fatal error: {e}[/red]")
        if args.verbose:
            import traceback
            traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
