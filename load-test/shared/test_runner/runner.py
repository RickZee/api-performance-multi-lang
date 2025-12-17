"""Main test runner orchestrator."""

import os
import sys
import time
import threading
import subprocess
from pathlib import Path
from typing import Dict, List, Optional
from rich.console import Console
from rich.live import Live
from rich.text import Text
from rich.panel import Panel

from .config import TestConfig, TestMode, APIConfig, ConfigManager
from .ui import TestRunnerUI
from .executor import TestExecutor

# Import K6MetricsParser from test-progress-display.py
# Use importlib to handle the import properly
import importlib.util
test_progress_display_path = Path(__file__).parent.parent / "test-progress-display.py"
if test_progress_display_path.exists():
    spec = importlib.util.spec_from_file_location("test_progress_display", test_progress_display_path)
    test_progress_display = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(test_progress_display)
    K6MetricsParser = test_progress_display.K6MetricsParser
else:
    K6MetricsParser = None


class TestRunner:
    """Main test runner orchestrator."""
    
    def __init__(self, config: TestConfig, console: Optional[Console] = None):
        self.config = config
        # Force console to be interactive and enable markup
        self.console = console or Console(force_terminal=True, force_interactive=True)
        self.ui = TestRunnerUI(self.console)
        self.executor = TestExecutor(str(config.base_dir), self.console)
        self.results: List[Dict] = []
        self.current_test_metrics: Optional[Dict] = None
        self.metrics_parser: Optional[K6MetricsParser] = None
        self.metrics_thread: Optional[threading.Thread] = None
        self.stop_metrics = threading.Event()
    
    def run(self) -> int:
        """Run all tests and return exit code (0 = success, 1 = failure)."""
        # Determine APIs to test
        api_names = self.config.api_names if self.config.api_names else ConfigManager.ALL_APIS
        
        # Validate API names
        for api_name in api_names:
            if not ConfigManager.validate_api_name(api_name):
                self.console.print(f"[red]Invalid API name: {api_name}[/red]")
                return 1
        
        # Get payload sizes
        payload_sizes = ConfigManager.get_payload_sizes(self.config.test_mode, self.config.payload_sizes)
        
        # Calculate total tests
        total_tests = len(api_names) * len(payload_sizes)
        
        # Create initial dashboard
        header = self.ui.create_header_panel(
            self.config.test_mode.value,
            len(api_names),
            payload_sizes
        )
        progress = self.ui.create_progress_panel(0, total_tests)
        status = self.ui.create_status_panel("", payload_sizes[0] if payload_sizes else "400b", "waiting")
        layout = self.ui.create_dashboard_layout(header, progress, status)
        
        # Ensure database is running
        try:
            if not self.executor.ensure_database_running():
                self.console.print("[red]Failed to start database. Aborting.[/red]")
                return 1
        except Exception as e:
            self.console.print(f"[red]Error ensuring database: {e}[/red]")
            if self.config.verbose:
                import traceback
                self.console.print(traceback.format_exc())
            return 1
        
        # Run tests with live dashboard
        current_test = 0
        failed_tests = 0
        
        # Use Live display with proper console configuration
        # screen=False keeps the display visible after completion
        # refresh_per_second=4 updates 4 times per second for smooth updates
        with Live(layout, console=self.console, refresh_per_second=4, screen=False, auto_refresh=True) as live:
            for api_name in api_names:
                api_config = ConfigManager.get_api_config(api_name)
                if not api_config:
                    self.console.print(f"[red]Failed to get config for {api_name}[/red]")
                    failed_tests += 1
                    continue
                
                for payload_size in payload_sizes:
                    current_test += 1
                    
                    # Update progress with colored API name
                    colored_api_name = self.ui.format_api_name(api_name)
                    progress = self.ui.create_progress_panel(
                        current_test,
                        total_tests,
                        f"{colored_api_name} ({payload_size})"
                    )
                    
                    # Update status to running
                    status = self.ui.create_status_panel(
                        api_name,
                        payload_size,
                        "running"
                    )
                    
                    # Update layout
                    layout["left"]["progress"].update(progress)
                    layout["left"]["status"].update(status)
                    live.update(layout)
                    
                    # Small delay to ensure UI is visible
                    import time
                    time.sleep(0.1)
                    
                    # Run the test
                    test_result = self._run_single_test(
                        api_config,
                        payload_size,
                        layout,
                        live
                    )
                    
                    # Record result
                    result = {
                        'api_name': api_name,
                        'payload_size': payload_size,
                        'status': 'completed' if test_result['success'] else 'failed',
                        'metrics': test_result.get('metrics', {}),
                    }
                    self.results.append(result)
                    
                    if not test_result['success']:
                        failed_tests += 1
                    
                    # Update results table
                    results_table = self.ui.create_results_table(self.results)
                    layout["right"].update(results_table)
                    live.update(layout)
        
        # Keep dashboard visible for a moment to see final state
        import time
        time.sleep(2)  # Pause to see final dashboard state
        
        # Show final summary (don't clear, just add to what's shown)
        self.console.print()  # Add spacing
        self._show_final_summary(failed_tests, total_tests)
        
        return 0 if failed_tests == 0 else 1
    
    def _run_single_test(self, api_config: APIConfig, payload_size: str,
                        layout, live, max_retries: int = 2) -> Dict:
        """Run a single test and return result."""
        result = {'success': False, 'metrics': {}}
        
        for retry in range(max_retries + 1):
            try:
                if retry > 0:
                    self.console.print(f"[yellow]Retrying test (attempt {retry + 1}/{max_retries + 1})...[/yellow]")
                    time.sleep(5)  # Wait before retry
                
                # Stop all APIs
                if not self.executor.stop_all_apis():
                    if retry < max_retries:
                        continue
                    return result
                time.sleep(2)
                
                # Clear database
                if not self.executor.clear_database():
                    if retry < max_retries:
                        continue
                    self.console.print(f"[yellow]Warning: Failed to clear database, continuing anyway...[/yellow]")
                
                # Start API
                if not self.executor.start_api(api_config):
                    self.console.print(f"[red]Failed to start {api_config.name}[/red]")
                    if retry < max_retries:
                        time.sleep(5)  # Wait before retry
                        continue
                    return result
                
                # Wait for API to be healthy (give it more time for gRPC APIs)
                status = self.ui.create_status_panel(
                    api_config.name,
                    payload_size,
                    "waiting",
                    None,
                    None
                )
                layout["left"]["status"].update(status)
                live.update(layout)
                
                health_check_timeout = 90 if api_config.protocol == "grpc" else 60
                if not self.executor.check_api_health(api_config, max_attempts=health_check_timeout):
                    self.console.print(f"[red]{api_config.name} failed health check after {health_check_timeout} attempts[/red]")
                    # Show container logs for debugging
                    try:
                        logs_result = subprocess.run(
                            ["docker", "logs", "--tail", "20", api_config.name],
                            cwd=self.config.base_dir,
                            capture_output=True,
                            text=True,
                            timeout=5,
                        )
                        if logs_result.stdout:
                            self.console.print(f"[yellow]Container logs:\n{logs_result.stdout}[/yellow]")
                    except Exception:
                        pass
                    if retry < max_retries:
                        time.sleep(5)  # Wait before retry
                        continue
                    return result
                
                # Determine JSON file path before running test
                # We need to create the path that k6 will use
                api_results_dir = Path(self.config.results_dir) / api_config.name
                if payload_size:
                    api_results_dir = api_results_dir / payload_size
                api_results_dir.mkdir(parents=True, exist_ok=True)
                
                timestamp = time.strftime("%Y%m%d_%H%M%S")
                json_filename = f"{api_config.name}-throughput-{self.config.test_mode.value}-{payload_size}-{timestamp}.json"
                json_file_path = str(api_results_dir / json_filename)
                
                # Start metrics monitoring in background before k6 starts
                self.stop_metrics.clear()
                self.metrics_thread = None
                
                if json_file_path and K6MetricsParser:
                    self.metrics_thread = threading.Thread(
                        target=self._monitor_metrics,
                        args=(json_file_path, layout, live, api_config, payload_size),
                        daemon=True
                    )
                    self.metrics_thread.start()
                
                # Run k6 test (this will create and write to the JSON file)
                success, actual_json_path = self.executor.run_k6_test(
                    api_config,
                    self.config.test_mode,
                    payload_size,
                    json_file_path  # Pass the expected path
                )
                
                # Use actual path returned (should match what we passed)
                if actual_json_path:
                    json_file_path = actual_json_path
                
                if not success:
                    if retry < max_retries:
                        continue
                    return result
                
                # Wait a moment for metrics thread to finish reading
                time.sleep(1)
                
                # Extract metrics
                metrics = self.executor.extract_test_metrics(json_file_path)
                if metrics:
                    result['metrics'] = metrics
                
                result['success'] = True
                break  # Success, exit retry loop
                
            except KeyboardInterrupt:
                raise  # Re-raise keyboard interrupt
            except Exception as e:
                self.console.print(f"[red]Error running test: {e}[/red]")
                if self.config.verbose:
                    import traceback
                    self.console.print(traceback.format_exc())
                if retry < max_retries:
                    continue
                result['success'] = False
                break
        
        # Cleanup (outside retry loop)
        try:
            # Stop API
            self.executor.stop_all_apis()
        except Exception as e:
            if self.config.verbose:
                self.console.print(f"[yellow]Warning: Error stopping API: {e}[/yellow]")
        
        # Stop metrics monitoring
        self.stop_metrics.set()
        if self.metrics_thread:
            self.metrics_thread.join(timeout=3)
        
        return result
    
    def _monitor_metrics(self, json_file: str, layout, live, api_config: APIConfig, payload_size: str):
        """Monitor k6 metrics in background thread."""
        if not K6MetricsParser:
            return
        
        # Wait for file to exist (k6 creates it when it starts)
        max_wait = 60
        waited = 0
        while waited < max_wait and not os.path.exists(json_file) and not self.stop_metrics.is_set():
            time.sleep(0.5)
            waited += 1
        
        if not os.path.exists(json_file) or self.stop_metrics.is_set():
            return
        
        try:
            parser = K6MetricsParser(json_file)
            phase_info = ConfigManager.get_phase_info(self.config.test_mode)
            last_update_time = time.time()
            
            while not self.stop_metrics.is_set():
                has_updates = parser.read_new_lines()
                stats = parser.get_statistics()
                
                # Detect current phase
                current_phase_num = 1
                for phase in reversed(phase_info):
                    if stats.get('current_vus', 0) >= phase['vus']:
                        current_phase_num = phase['num']
                        break
                
                current_phase = next(
                    (p for p in phase_info if p['num'] == current_phase_num),
                    phase_info[0] if phase_info else None
                )
                
                # Update status panel periodically (every second)
                current_time = time.time()
                if current_time - last_update_time >= 1.0:
                    status = self.ui.create_status_panel(
                        api_config.name,
                        payload_size,
                        "running",
                        current_phase,
                        stats
                    )
                    try:
                        layout["left"]["status"].update(status)
                        live.update(layout)
                    except Exception:
                        # Layout might have been closed, exit gracefully
                        break
                    last_update_time = current_time
                
                # Check if test is complete (no updates for a while and we have data)
                if stats.get('duration_seconds', 0) > 0 and not has_updates:
                    # Wait a bit more to see if test is really done
                    time.sleep(2)
                    if not parser.read_new_lines():
                        break
                
                time.sleep(0.5)
        except Exception as e:
            # Silently handle errors in monitoring thread
            pass
    
    def _show_final_summary(self, failed_tests: int, total_tests: int):
        """Show final test summary."""
        # Create a nice summary panel
        from rich.panel import Panel
        from rich.columns import Columns
        
        self.console.print()  # Blank line
        
        # Summary stats in a panel
        passed = total_tests - failed_tests
        summary_text = f"[bold green]✓ Passed:[/bold green] {passed}"
        if failed_tests > 0:
            summary_text += f"  [bold red]✗ Failed:[/bold red] {failed_tests}"
        summary_text += f"  [bold]Total:[/bold] {total_tests}"
        
        summary_panel = Panel(summary_text, title="[bold blue]Test Execution Summary[/bold blue]", border_style="blue")
        self.console.print(summary_panel)
        self.console.print()
        
        # Results table
        results_table = self.ui.create_results_table(self.results)
        self.console.print(results_table)
        self.console.print()
        
        # Export results if requested
        self._export_results()
    
    def _export_results(self):
        """Export results to JSON file."""
        try:
            import json
            from datetime import datetime
            
            # Create export directory
            export_dir = Path(self.config.results_dir).parent / "exports"
            export_dir.mkdir(parents=True, exist_ok=True)
            
            # Generate filename
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            export_file = export_dir / f"test-results-{self.config.test_mode.value}-{timestamp}.json"
            
            # Prepare export data
            export_data = {
                'test_mode': self.config.test_mode.value,
                'timestamp': timestamp,
                'total_tests': len(self.results),
                'passed': sum(1 for r in self.results if r.get('status') == 'completed'),
                'failed': sum(1 for r in self.results if r.get('status') == 'failed'),
                'results': self.results,
            }
            
            # Write to file
            with open(export_file, 'w') as f:
                json.dump(export_data, f, indent=2)
            
            if self.config.verbose:
                self.console.print(f"[green]Results exported to: {export_file}[/green]")
        except Exception as e:
            if self.config.verbose:
                self.console.print(f"[yellow]Warning: Failed to export results: {e}[/yellow]")
