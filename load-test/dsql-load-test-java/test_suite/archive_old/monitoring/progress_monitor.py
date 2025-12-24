"""
Real-time progress monitoring with rich output.
"""

import time
import json
from pathlib import Path
from typing import Optional, List
from datetime import datetime
from rich.console import Console
from rich.progress import Progress, BarColumn, TextColumn, TimeElapsedColumn
from rich.panel import Panel
from rich.table import Table
from rich.live import Live
from rich.layout import Layout

from test_suite.monitoring.status_checker import StatusChecker
from test_suite.config.loader import TestConfigLoader


class ProgressMonitor:
    """Real-time progress monitoring with rich output."""
    
    def __init__(self, results_dir: str, instance_id: str, region: str, total_tests: Optional[int] = None):
        self.results_dir = Path(results_dir)
        self.console = Console()
        self.status_checker = StatusChecker(instance_id, region, self.results_dir)
        
        # Calculate total tests from manifest if not provided
        if total_tests is None:
            manifest_path = self.results_dir / 'manifest.json'
            if manifest_path.exists():
                try:
                    with open(manifest_path, 'r') as f:
                        manifest = json.load(f)
                    # Read total_expected from manifest (most accurate)
                    total_tests = manifest.get('total_expected', 0)
                    if total_tests == 0:
                        # Fallback: count tests in manifest
                        total_tests = len(manifest.get('tests', []))
                except Exception:
                    total_tests = 0
        
        self.total_tests = total_tests
        self.start_time = self._get_start_time()
    
    def _get_start_time(self) -> float:
        """Get start time from manifest."""
        manifest_path = self.results_dir / 'manifest.json'
        if manifest_path.exists():
            try:
                with open(manifest_path, 'r') as f:
                    manifest = json.load(f)
                    start_str = manifest.get('start_time', '')
                    if start_str:
                        # Parse ISO timestamp
                        dt = datetime.fromisoformat(start_str.replace('Z', '+00:00'))
                        return dt.timestamp()
            except Exception:
                pass
        
        return time.time()
    
    def _get_initiated_test_count(self) -> Optional[int]:
        """Get count of tests actually initiated from manifest."""
        manifest_path = self.results_dir / 'manifest.json'
        if manifest_path.exists():
            try:
                with open(manifest_path, 'r') as f:
                    manifest = json.load(f)
                    # Use total_expected if available (most accurate)
                    total_expected = manifest.get('total_expected', 0)
                    if total_expected > 0:
                        return total_expected
                    # Fallback: count tests in manifest
                    tests = manifest.get('tests', [])
                    return len(tests) if tests else None
            except Exception:
                pass
        return None
    
    def _get_completed_count_from_manifest(self) -> Optional[int]:
        """Get count of completed tests from manifest (more accurate than JSON files)."""
        manifest_path = self.results_dir / 'manifest.json'
        if manifest_path.exists():
            try:
                with open(manifest_path, 'r') as f:
                    manifest = json.load(f)
                    tests = manifest.get('tests', [])
                    # Count completed tests
                    return sum(1 for t in tests if t.get('status') == 'completed')
            except Exception:
                pass
        return None
    
    def format_duration(self, seconds: float) -> str:
        """Format duration as human-readable string."""
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        secs = int(seconds % 60)
        
        if hours > 0:
            return f"{hours}h {minutes}m {secs}s"
        elif minutes > 0:
            return f"{minutes}m {secs}s"
        else:
            return f"{secs}s"
    
    def display_progress(self, completed: int, current_test: Optional[str] = None) -> None:
        """Display formatted progress with progress bar."""
        # Get actual total from manifest (tests actually initiated)
        total_initiated = self._get_initiated_test_count()
        total_expected = total_initiated if total_initiated is not None else self.total_tests
        
        elapsed = time.time() - self.start_time
        # Ensure total_expected is not None
        if total_expected is None:
            total_expected = 0
        remaining = max(0, total_expected - completed)
        progress_pct = (completed / total_expected * 100) if total_expected > 0 else 0
        
        # Calculate estimates
        avg_per_test = elapsed / completed if completed > 0 else 0
        est_remaining = avg_per_test * remaining
        est_total = elapsed + est_remaining
        
        # Create layout
        layout = Layout()
        
        # Header
        header = Panel(
            "[bold cyan]DSQL Performance Test Suite - Progress Monitor[/bold cyan]",
            border_style="cyan"
        )
        
        # Progress section
        progress_table = Table.grid(padding=(0, 2))
        progress_table.add_row(
            "[bold]Test Progress[/bold]",
            f"Completed: [green]{completed}[/green] / {total_expected} tests",
            f"Remaining: [yellow]{remaining}[/yellow] tests"
        )
        progress_table.add_row("", f"Progress: [bold]{progress_pct:.0f}%[/bold]", "")
        
        # Progress bar
        bar_width = 50
        filled = int(bar_width * progress_pct / 100)
        bar = "█" * filled + "░" * (bar_width - filled)
        progress_table.add_row("", f"[green]{bar}[/green]", "")
        
        # Timing section
        timing_table = Table.grid(padding=(0, 2))
        timing_table.add_row("[bold]Timing Information[/bold]", "")
        timing_table.add_row("Elapsed:", f"[cyan]{self.format_duration(elapsed)}[/cyan]")
        timing_table.add_row("Avg per test:", f"[cyan]{self.format_duration(avg_per_test)}[/cyan]")
        timing_table.add_row("Est. remaining:", f"[yellow]{self.format_duration(est_remaining)}[/yellow]")
        timing_table.add_row("Est. total:", f"[cyan]{self.format_duration(est_total)}[/cyan]")
        
        # Current status
        status_table = Table.grid(padding=(0, 2))
        status_table.add_row("[bold]Current Status[/bold]", "")
        
        # Get completed tests to check if suite is done
        completed_tests = self.status_checker.get_completed_tests()
        
        # Get actual total from manifest (tests actually initiated)
        total_expected = self._get_initiated_test_count()
        if total_expected is None:
            # Fallback to config total
            total_expected = self.total_tests
        
        # First, check manifest for running test (most reliable)
        running_test_from_manifest = self.status_checker.get_running_test_from_manifest()
        if running_test_from_manifest:
            test_id = running_test_from_manifest.get('test_id', '?')
            scenario = str(running_test_from_manifest.get('scenario', '?'))
            threads = str(running_test_from_manifest.get('threads', '?'))
            iterations = str(running_test_from_manifest.get('iterations', '?'))
            count = str(running_test_from_manifest.get('count', '?'))
            
            test_display = test_id
            if len(test_display) > 50:
                test_display = test_display[:47] + "..."
            
            status_table.add_row("Currently Running:", f"[bold yellow]{test_display}[/bold yellow]")
            status_table.add_row("", f"Scenario {scenario}, Threads: {threads}, Iterations: {iterations}, Count: {count}")
        # Fallback: Check if there's an active command even if we can't get test ID from manifest
        elif self.status_checker.get_active_command():
            active_cmd = self.status_checker.get_active_command()
            if current_test:
                # Get detailed test info
                test_info = self.status_checker.get_current_test_info()
                if test_info:
                    scenario = test_info.get('scenario', '?')
                    threads = test_info.get('threads', '?')
                    iterations = test_info.get('iterations', '?')
                    count = test_info.get('count', '?')
                    
                    # Format test display
                    test_display = current_test
                    if len(test_display) > 50:
                        # Truncate long test IDs
                        test_display = test_display[:47] + "..."
                    
                    status_table.add_row("Currently Running:", f"[bold yellow]{test_display}[/bold yellow]")
                    status_table.add_row("", f"Scenario {scenario}, Threads: {threads}, Iterations: {iterations}, Count: {count}")
                else:
                    # Parse test ID manually if info extraction failed
                    import re
                    scenario_match = re.search(r'scenario(\d+)', current_test)
                    threads_match = re.search(r'threads(\d+)', current_test)
                    loops_match = re.search(r'loops(\d+)', current_test)
                    count_match = re.search(r'count(\d+)', current_test)
                    
                    scenario = scenario_match.group(1) if scenario_match else "?"
                    threads = threads_match.group(1) if threads_match else "?"
                    iterations = loops_match.group(1) if loops_match else "?"
                    count = count_match.group(1) if count_match else "?"
                    
                    test_display = current_test
                    if len(test_display) > 50:
                        test_display = test_display[:47] + "..."
                    
                    status_table.add_row("Currently Running:", f"[bold yellow]{test_display}[/bold yellow]")
                    status_table.add_row("", f"Scenario {scenario}, Threads: {threads}, Iterations: {iterations}, Count: {count}")
            else:
                # Try to infer from completed tests and manifest
                next_test_info = self.status_checker.get_next_expected_test()
                if next_test_info:
                    test_id = next_test_info.get('test_id', 'test-???')
                    scenario = next_test_info.get('scenario', '?')
                    threads = next_test_info.get('threads', '?')
                    iterations = next_test_info.get('iterations', '?')
                    count = next_test_info.get('count', '?')
                    
                    status_table.add_row("Currently Running:", f"[bold yellow]{test_id}[/bold yellow]")
                    status_table.add_row("", f"Scenario {scenario}, Threads: {threads}, Iterations: {iterations}, Count: {count}")
                else:
                    # Fallback: try to infer from completed tests
                    completed_tests = self.status_checker.get_completed_tests()
                    if completed_tests:
                        last_test = completed_tests[-1]
                        # Extract test number and increment
                        import re
                        match = re.search(r'test-(\d{3})', last_test)
                        if match:
                            next_num = int(match.group(1)) + 1
                            # Try to infer details from last test pattern
                            scenario_match = re.search(r'scenario(\d+)', last_test)
                            scenario = scenario_match.group(1) if scenario_match else "?"
                            
                            status_table.add_row("Currently Running:", f"[bold yellow]test-{next_num:03d} (Scenario {scenario})[/bold yellow]")
                            status_table.add_row("", "[dim]Extracting details...[/dim]")
                        else:
                            status_table.add_row("Currently Running:", "[bold yellow]Test in progress...[/bold yellow]")
                    else:
                        status_table.add_row("Currently Running:", "[bold yellow]Test in progress...[/bold yellow]")
        elif current_test:
            test_info = self.status_checker.get_current_test_info()
            if test_info:
                scenario = test_info.get('scenario', '?')
                threads = test_info.get('threads', '?')
                iterations = test_info.get('iterations', '?')
                count = test_info.get('count', '?')
                
                test_display = current_test
                if len(test_display) > 50:
                    test_display = test_display[:47] + "..."
                
                status_table.add_row("Currently Running:", f"[bold yellow]{test_display}[/bold yellow]")
                status_table.add_row("", f"Scenario {scenario}, Threads: {threads}, Iterations: {iterations}, Count: {count}")
            else:
                # Parse manually
                import re
                scenario_match = re.search(r'scenario(\d+)', current_test)
                threads_match = re.search(r'threads(\d+)', current_test)
                scenario = scenario_match.group(1) if scenario_match else "?"
                threads = threads_match.group(1) if threads_match else "?"
                
                test_display = current_test
                if len(test_display) > 50:
                    test_display = test_display[:47] + "..."
                
                status_table.add_row("Currently Running:", f"[bold yellow]{test_display}[/bold yellow]")
                status_table.add_row("", f"Scenario {scenario}, Threads: {threads}")
        else:
            # No active command - check if suite is complete
            if total_expected and len(completed_tests) >= total_expected:
                status_table.add_row("Currently Running:", "[bold green]✓ Suite Complete[/bold green]")
                if completed_tests:
                    last_test = completed_tests[-1]
                    import re
                    scenario_match = re.search(r'scenario(\d+)', last_test)
                    threads_match = re.search(r'threads(\d+)', last_test)
                    loops_match = re.search(r'loops(\d+)', last_test)
                    count_match = re.search(r'count(\d+)', last_test)
                    payload_match = re.search(r'-payload([^-]+)', last_test)
                    
                    scenario = scenario_match.group(1) if scenario_match else "?"
                    threads = threads_match.group(1) if threads_match else "?"
                    iterations = loops_match.group(1) if loops_match else "?"
                    count = count_match.group(1) if count_match else "?"
                    payload = payload_match.group(1) if payload_match else "default"
                    
                    status_table.add_row("Last Completed:", f"[dim]Scenario {scenario}, Threads: {threads}, Iterations: {iterations}, Count: {count}, Payload: {payload}[/dim]")
            elif completed_tests:
                # Tests are done but might be waiting for next
                last_test = completed_tests[-1]
                import re
                scenario_match = re.search(r'scenario(\d+)', last_test)
                threads_match = re.search(r'threads(\d+)', last_test)
                loops_match = re.search(r'loops(\d+)', last_test)
                count_match = re.search(r'count(\d+)', last_test)
                payload_match = re.search(r'-payload([^-]+)', last_test)
                
                scenario = scenario_match.group(1) if scenario_match else "?"
                threads = threads_match.group(1) if threads_match else "?"
                iterations = loops_match.group(1) if loops_match else "?"
                count = count_match.group(1) if count_match else "?"
                payload = payload_match.group(1) if payload_match else "default"
                
                status_table.add_row("Currently Running:", "[dim]Waiting for next test...[/dim]")
                status_table.add_row("Last Completed:", f"[dim]Scenario {scenario}, Threads: {threads}, Iterations: {iterations}, Count: {count}, Payload: {payload}[/dim]")
            else:
                status_table.add_row("Currently Running:", "[dim]None detected[/dim]")
                status_table.add_row("", "[dim]No tests started yet[/dim]")
        
        # Combine into layout
        layout.split_column(
            Layout(header, size=3),
            Layout(Panel(progress_table, title="📊 Test Progress", border_style="blue"), size=6),
            Layout(Panel(timing_table, title="⏱️  Timing Information", border_style="blue"), size=7),
            Layout(Panel(status_table, title="🔄 Current Status", border_style="blue"), size=6)
        )
        
        self.console.print(layout)
    
    def monitor_loop(self, check_interval: int = 10, auto_generate_report: bool = True) -> None:
        """Main monitoring loop."""
        try:
            while True:
                self.console.clear()
                
                # Get current status
                completed_tests = self.status_checker.get_completed_tests()
                completed = len(completed_tests)
                current_test = self.status_checker.get_current_test_id()
                
                # Get actual total from manifest
                total_initiated = self._get_initiated_test_count()
                
                # Also check manifest for completed count (more accurate than JSON files)
                completed_from_manifest = self._get_completed_count_from_manifest()
                if completed_from_manifest is not None:
                    completed = completed_from_manifest
                
                # Check if all initiated tests are complete
                if total_initiated and completed >= total_initiated:
                    # All tests complete - show final status
                    self.display_progress(completed, current_test)
                    self.console.print("\n[bold green]✓ All tests completed![/bold green]")
                    
                    if auto_generate_report:
                        self.console.print("\n[yellow]Generating charts and markdown report...[/yellow]")
                        try:
                            # Generate charts first if they don't exist
                            self._ensure_charts_exist()
                            # Then generate the report
                            report_path = self._generate_markdown_report()
                            self.console.print("[bold green]✓ Report generated successfully![/bold green]")
                            
                            # Try to show relative path if possible
                            try:
                                from pathlib import Path
                                rel_path = Path(report_path).relative_to(Path.cwd())
                                display_path = str(rel_path) if len(str(rel_path)) < len(report_path) else report_path
                            except (ValueError, Exception):
                                display_path = report_path
                            
                            # Detect OS and show appropriate command
                            import platform
                            os_type = platform.system()
                            if os_type == 'Darwin':  # macOS
                                open_cmd = "open"
                            elif os_type == 'Linux':
                                open_cmd = "xdg-open"
                            elif os_type == 'Windows':
                                open_cmd = "start"
                            else:
                                open_cmd = "open"  # fallback
                            
                            self.console.print(f"\n[bold]Report saved to:[/bold]")
                            self.console.print(f"  [cyan]{display_path}[/cyan]")
                            self.console.print(f"\n[bold]To open:[/bold]")
                            self.console.print(f"  [cyan]{open_cmd} {display_path}[/cyan]")
                            self.console.print("  Or open in your editor/IDE")
                        except Exception as e:
                            self.console.print(f"[red]✗ Failed to generate report: {e}[/red]")
                    
                    self.console.print("\n[dim]Press Ctrl+C to exit[/dim]")
                    # Wait a bit before exiting to show final status
                    time.sleep(5)
                    break
                
                # Display progress
                self.display_progress(completed, current_test)
                
                # Wait for next check
                time.sleep(check_interval)
                
        except KeyboardInterrupt:
            self.console.print("\n[yellow]Monitoring stopped by user[/yellow]")
    
    def _ensure_charts_exist(self) -> None:
        """Ensure charts are generated before creating report."""
        charts_dir = self.results_dir / 'charts'
        
        # Check if charts directory exists and has PNG files
        if charts_dir.exists() and list(charts_dir.glob('*.png')):
            return  # Charts already exist
        
        # Try to generate charts using analyze_results.py
        import subprocess
        import sys
        from pathlib import Path
        
        script_dir = Path(__file__).parent.parent.parent
        analyze_script = script_dir / 'scripts' / 'analyze_results.py'
        
        if analyze_script.exists():
            self.console.print("[dim]Generating charts...[/dim]")
            result = subprocess.run(
                [sys.executable, str(analyze_script), str(self.results_dir)],
                capture_output=True,
                text=True
            )
            if result.returncode == 0:
                self.console.print("[dim]✓ Charts generated[/dim]")
            else:
                # Try alternative chart generation script
                chart_script = script_dir / 'create-comprehensive-charts.py'
                if chart_script.exists():
                    result = subprocess.run(
                        [sys.executable, str(chart_script), str(self.results_dir)],
                        capture_output=True,
                        text=True
                    )
    
    def _generate_markdown_report(self) -> str:
        """Generate markdown report after tests complete. Returns path to report file."""
        import subprocess
        import sys
        import re
        from pathlib import Path
        
        # Find the generate_markdown_report.py script
        script_dir = Path(__file__).parent.parent.parent
        report_script = script_dir / 'scripts' / 'generate_markdown_report.py'
        
        if not report_script.exists():
            raise FileNotFoundError(f"Report script not found: {report_script}")
        
        # Run the report generation script
        result = subprocess.run(
            [sys.executable, str(report_script), str(self.results_dir)],
            capture_output=True,
            text=True
        )
        
        if result.returncode != 0:
            raise RuntimeError(f"Report generation failed: {result.stderr}")
        
        # Try to extract report path from stdout (script prints "✅ Markdown report generated: {path}")
        stdout = result.stdout.strip()
        match = re.search(r'Markdown report generated:\s*(.+)', stdout)
        if match:
            report_path = match.group(1).strip()
            if Path(report_path).exists():
                return report_path
        
        # Fallback: The report is typically saved as REPORT.md in the results directory
        report_path = self.results_dir / 'REPORT.md'
        if report_path.exists():
            return str(report_path)
        
        # Try alternative names
        for alt_name in ['report.md', 'TestReport.md', 'test-report.md']:
            alt_path = self.results_dir / alt_name
            if alt_path.exists():
                return str(alt_path)
        
        # If not found, return expected path anyway
        return str(report_path)

