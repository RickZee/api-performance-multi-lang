#!/usr/bin/env python3
"""
Animated CLI Test Progress Display
Displays real-time test progress with progress bars and formatted statistics
"""

import json
import sys
import os
import time
import argparse
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from collections import deque

# Try to import rich, fall back to basic mode if not available
try:
    from rich.console import Console
    from rich.live import Live
    from rich.progress import Progress, BarColumn, TextColumn, TimeElapsedColumn, SpinnerColumn
    from rich.table import Table
    from rich.panel import Panel
    from rich.layout import Layout
    from rich.text import Text
    from rich import box
    RICH_AVAILABLE = True
except ImportError:
    RICH_AVAILABLE = False
    # Fallback: basic terminal control
    import subprocess
    import shutil


class K6MetricsParser:
    """Parse k6 NDJSON output in real-time"""
    
    def __init__(self, json_file: str):
        self.json_file = json_file
        self.start_time = None
        self.current_time = None
        self.metrics = {
            'http_req_duration': deque(maxlen=10000),  # Individual request durations
            'grpc_req_duration': deque(maxlen=10000),
            'http_req_failed': deque(maxlen=10000),  # Individual request failures (0 or 1)
            'grpc_req_failed': deque(maxlen=10000),
            'http_reqs_cumulative': deque(maxlen=100),  # Cumulative request counts
            'grpc_reqs_cumulative': deque(maxlen=100),
            'iterations': deque(maxlen=100),
            'vus': deque(maxlen=100),
        }
        self.last_position = 0
        self.total_requests = 0
        self.total_failed = 0
        self.current_vus = 0
        self.total_iterations = 0
        self.latest_cumulative_reqs = 0
        
    def read_new_lines(self) -> bool:
        """Read new lines from JSON file since last read"""
        if not os.path.exists(self.json_file):
            return False
        
        try:
            with open(self.json_file, 'r') as f:
                # Seek to last position
                try:
                    f.seek(self.last_position)
                except (IOError, OSError):
                    # File might have been truncated or reset, start from beginning
                    self.last_position = 0
                    f.seek(0)
                
                new_lines = f.readlines()
                new_position = f.tell()
                
                # Only update if we got new data
                if new_position > self.last_position:
                    self.last_position = new_position
                    
                    # Parse new lines
                    for line in new_lines:
                        line = line.strip()
                        if not line:
                            continue
                        
                        try:
                            obj = json.loads(line)
                            self._process_metric(obj)
                        except json.JSONDecodeError:
                            continue
                    
                    return True
                
                return False
        except (IOError, OSError, PermissionError):
            # File might be locked or not readable yet
            return False
        except Exception:
            return False
    
    def _process_metric(self, obj: Dict):
        """Process a single metric object from NDJSON"""
        obj_type = obj.get('type', '')
        metric_name = obj.get('metric', '')
        data = obj.get('data', {})
        
        # Track time
        if 'time' in data:
            time_str = data['time']
            try:
                if time_str.endswith('Z'):
                    time_str = time_str[:-1] + '+00:00'
                time_obj = datetime.fromisoformat(time_str)
                timestamp = time_obj.timestamp()
                
                if self.start_time is None:
                    self.start_time = timestamp
                self.current_time = timestamp
            except Exception:
                pass
        
        # Process different metric types
        if obj_type == 'Point':
            if metric_name == 'http_reqs':
                # Cumulative request count
                value = data.get('value', 0)
                self.metrics['http_reqs_cumulative'].append(value)
                self.latest_cumulative_reqs = value
                self.total_requests = max(self.total_requests, value)
            elif metric_name == 'grpc_reqs':
                # Cumulative request count
                value = data.get('value', 0)
                self.metrics['grpc_reqs_cumulative'].append(value)
                self.latest_cumulative_reqs = value
                self.total_requests = max(self.total_requests, value)
            elif metric_name == 'http_req_duration':
                # Individual request duration (each point = 1 request)
                value = data.get('value', 0)
                self.metrics['http_req_duration'].append(value)
                # Each duration point represents one request
                if not self.latest_cumulative_reqs:
                    self.total_requests = len(self.metrics['http_req_duration'])
            elif metric_name == 'grpc_req_duration':
                # Individual request duration (each point = 1 request)
                value = data.get('value', 0)
                self.metrics['grpc_req_duration'].append(value)
                # Each duration point represents one request
                if not self.latest_cumulative_reqs:
                    self.total_requests = len(self.metrics['grpc_req_duration'])
            elif metric_name == 'http_req_failed':
                # Individual request failure (0 = success, 1 = failed)
                value = data.get('value', 0)
                self.metrics['http_req_failed'].append(value)
                if value > 0:
                    self.total_failed += 1
            elif metric_name == 'grpc_req_failed':
                # Individual request failure (0 = success, 1 = failed)
                value = data.get('value', 0)
                self.metrics['grpc_req_failed'].append(value)
                if value > 0:
                    self.total_failed += 1
            elif metric_name == 'iterations':
                value = data.get('value', 0)
                self.metrics['iterations'].append(value)
                self.total_iterations = max(self.total_iterations, value)
            elif metric_name == 'vus':
                value = data.get('value', 0)
                self.metrics['vus'].append(value)
                self.current_vus = value
    
    def get_statistics(self) -> Dict:
        """Calculate current statistics from collected metrics"""
        # Determine protocol - use duration points as they represent individual requests
        durations = list(self.metrics['http_req_duration']) or list(self.metrics['grpc_req_duration'])
        failed = list(self.metrics['http_req_failed']) or list(self.metrics['grpc_req_failed'])
        
        # Use cumulative request count if available, otherwise count duration points
        if self.latest_cumulative_reqs > 0:
            request_count = self.latest_cumulative_reqs
        else:
            request_count = len(durations)
        
        # Calculate duration
        duration_seconds = 0.0
        if self.start_time and self.current_time:
            duration_seconds = self.current_time - self.start_time
        elif durations:
            # Estimate from request count (assume ~100ms per request average)
            duration_seconds = max(0.1, len(durations) * 0.1)
        
        # Calculate throughput
        throughput = 0.0
        if duration_seconds > 0:
            throughput = request_count / duration_seconds if request_count > 0 else 0.0
        
        # Response time statistics
        avg_response = sum(durations) / len(durations) if durations else 0.0
        min_response = min(durations) if durations else 0.0
        max_response = max(durations) if durations else 0.0
        
        # Calculate percentiles
        p95 = 0.0
        p99 = 0.0
        if durations:
            sorted_durations = sorted(durations)
            p95_idx = int(len(sorted_durations) * 0.95)
            p99_idx = int(len(sorted_durations) * 0.99)
            p95 = sorted_durations[min(p95_idx, len(sorted_durations) - 1)]
            p99 = sorted_durations[min(p99_idx, len(sorted_durations) - 1)]
        
        # Error rate - count failures from failed metrics
        error_count = sum(1 for f in failed if f > 0) if failed else self.total_failed
        total_with_failures = len(failed) if failed else request_count
        error_rate = 0.0
        if total_with_failures > 0:
            error_rate = (error_count / total_with_failures) * 100
        
        # Successful requests
        successful = request_count - error_count
        
        return {
            'total_requests': request_count,
            'current_requests': len(durations),
            'successful': successful,
            'failed': error_count,
            'throughput': throughput,
            'avg_response': avg_response,
            'min_response': min_response,
            'max_response': max_response,
            'p95_response': p95,
            'p99_response': p99,
            'error_rate': error_rate,
            'duration_seconds': duration_seconds,
            'current_vus': self.current_vus,
            'total_iterations': self.total_iterations,
        }


class TestProgressDisplay:
    """Display animated test progress dashboard"""
    
    def __init__(self, json_file: str, api_name: str, test_mode: str, 
                 payload_size: str = "", expected_duration: int = 0):
        self.json_file = json_file
        self.api_name = api_name
        self.test_mode = test_mode
        self.payload_size = payload_size or "default"
        self.expected_duration = expected_duration
        self.parser = K6MetricsParser(json_file)
        self.console = Console() if RICH_AVAILABLE else None
        self.start_time = time.time()
        
        # Phase information
        self.phase_info = self._get_phase_info()
        self.current_phase = 1
        self.phase_start_time = None
        
    def _get_phase_info(self) -> List[Dict]:
        """Get phase information based on test mode"""
        if self.test_mode == 'smoke':
            return [{'num': 1, 'name': 'Smoke Test', 'duration': 30, 'vus': 10}]
        elif self.test_mode == 'full':
            return [
                {'num': 1, 'name': 'Baseline', 'duration': 120, 'vus': 10},
                {'num': 2, 'name': 'Mid-load', 'duration': 120, 'vus': 50},
                {'num': 3, 'name': 'High-load', 'duration': 120, 'vus': 100},
                {'num': 4, 'name': 'Higher-load', 'duration': 300, 'vus': 200},
            ]
        elif self.test_mode == 'saturation':
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
    
    def _detect_current_phase(self, current_vus: int) -> int:
        """Detect current phase based on VU count"""
        for phase in reversed(self.phase_info):
            if current_vus >= phase['vus']:
                return phase['num']
        return 1
    
    def _create_display_rich(self, stats: Dict) -> str:
        """Create display using rich library"""
        # Detect current phase
        self.current_phase = self._detect_current_phase(stats['current_vus'])
        current_phase_info = next((p for p in self.phase_info if p['num'] == self.current_phase), self.phase_info[0])
        
        # Calculate progress
        elapsed = stats['duration_seconds']
        total_expected = sum(p['duration'] for p in self.phase_info)
        overall_progress = min(100, (elapsed / total_expected * 100) if total_expected > 0 else 0)
        
        # Phase progress
        phase_elapsed = elapsed - sum(p['duration'] for p in self.phase_info if p['num'] < self.current_phase)
        phase_progress = min(100, (phase_elapsed / current_phase_info['duration'] * 100) if current_phase_info['duration'] > 0 else 0)
        
        # Create layout
        layout = Layout()
        
        # Header
        header_text = f"[bold blue]{self.api_name}[/bold blue] | Mode: [cyan]{self.test_mode}[/cyan] | Payload: [yellow]{self.payload_size}[/yellow] | Elapsed: [green]{self._format_duration(elapsed)}[/green]"
        layout["header"] = Panel(header_text, border_style="blue")
        
        # Progress section
        progress_table = Table.grid(padding=1)
        progress_table.add_column(style="cyan", width=20)
        progress_table.add_column(style="white")
        
        # Overall progress
        overall_bar = self._create_progress_bar(overall_progress / 100)
        progress_table.add_row("Overall Progress:", overall_bar)
        
        # Phase progress
        phase_text = f"Phase {self.current_phase}/{len(self.phase_info)}: {current_phase_info['name']} ({current_phase_info['vus']} VUs)"
        phase_bar = self._create_progress_bar(phase_progress / 100)
        progress_table.add_row(phase_text, phase_bar)
        
        layout["progress"] = Panel(progress_table, title="Progress", border_style="green")
        
        # Statistics section
        stats_table = Table.grid(padding=1)
        stats_table.add_column(style="cyan", width=25)
        stats_table.add_column(style="white", width=15)
        stats_table.add_column(style="cyan", width=25)
        stats_table.add_column(style="white", width=15)
        
        # Format error rate with color
        error_color = "green" if stats['error_rate'] < 1 else "yellow" if stats['error_rate'] < 5 else "red"
        error_text = f"[{error_color}]{stats['error_rate']:.2f}%[/{error_color}]"
        
        stats_table.add_row("Throughput:", f"[green]{stats['throughput']:.2f} req/s[/green]",
                          "Error Rate:", error_text)
        stats_table.add_row("Total Requests:", f"[white]{stats['total_requests']}[/white]",
                          "Successful:", f"[green]{stats['successful']}[/green]")
        stats_table.add_row("Failed:", f"[red]{stats['failed']}[/red]",
                          "Current VUs:", f"[cyan]{stats['current_vus']}[/cyan]")
        stats_table.add_row("Avg Response:", f"[white]{stats['avg_response']:.2f} ms[/white]",
                          "Min Response:", f"[green]{stats['min_response']:.2f} ms[/green]")
        stats_table.add_row("Max Response:", f"[yellow]{stats['max_response']:.2f} ms[/yellow]",
                          "P95 Response:", f"[yellow]{stats['p95_response']:.2f} ms[/yellow]")
        stats_table.add_row("P99 Response:", f"[red]{stats['p99_response']:.2f} ms[/red]",
                          "Iterations:", f"[cyan]{stats['total_iterations']}[/cyan]")
        
        layout["stats"] = Panel(stats_table, title="Statistics", border_style="yellow")
        
        # Combine layout
        layout.split_column(
            Layout(name="header", size=3),
            Layout(name="progress", size=5),
            Layout(name="stats", size=10),
        )
        
        return layout
    
    def _create_progress_bar(self, progress: float, width: int = 50) -> str:
        """Create a text progress bar"""
        filled = int(progress * width)
        bar = "█" * filled + "░" * (width - filled)
        percent = int(progress * 100)
        color = "green" if percent >= 90 else "yellow" if percent >= 50 else "cyan"
        return f"[{color}]{bar}[/{color}] {percent}%"
    
    def _format_duration(self, seconds: float) -> str:
        """Format duration as MM:SS"""
        m = int(seconds // 60)
        s = int(seconds % 60)
        return f"{m:02d}:{s:02d}"
    
    def _create_display_basic(self, stats: Dict) -> str:
        """Create display using basic ANSI codes (fallback)"""
        # Detect current phase
        self.current_phase = self._detect_current_phase(stats['current_vus'])
        current_phase_info = next((p for p in self.phase_info if p['num'] == self.current_phase), self.phase_info[0])
        
        # Calculate progress
        elapsed = stats['duration_seconds']
        total_expected = sum(p['duration'] for p in self.phase_info)
        overall_progress = min(100, (elapsed / total_expected * 100) if total_expected > 0 else 0)
        
        # Clear screen and move to top
        output = "\033[2J\033[H"  # Clear screen and move cursor to top
        
        # Header
        output += f"\033[1;34m{'='*80}\033[0m\n"
        output += f"\033[1;34m{self.api_name} | Mode: {self.test_mode} | Payload: {self.payload_size} | Elapsed: {self._format_duration(elapsed)}\033[0m\n"
        output += f"\033[1;34m{'='*80}\033[0m\n\n"
        
        # Progress bars
        overall_bar = self._create_progress_bar_basic(overall_progress / 100)
        output += f"Overall Progress: {overall_bar}\n"
        
        phase_text = f"Phase {self.current_phase}/{len(self.phase_info)}: {current_phase_info['name']} ({current_phase_info['vus']} VUs)"
        phase_elapsed = elapsed - sum(p['duration'] for p in self.phase_info if p['num'] < self.current_phase)
        phase_progress = min(100, (phase_elapsed / current_phase_info['duration'] * 100) if current_phase_info['duration'] > 0 else 0)
        phase_bar = self._create_progress_bar_basic(phase_progress / 100)
        output += f"{phase_text}: {phase_bar}\n\n"
        
        # Statistics
        output += f"\033[1;33mStatistics:\033[0m\n"
        output += f"  Throughput:     \033[32m{stats['throughput']:.2f} req/s\033[0m\n"
        error_color = "\033[32m" if stats['error_rate'] < 1 else "\033[33m" if stats['error_rate'] < 5 else "\033[31m"
        output += f"  Error Rate:     {error_color}{stats['error_rate']:.2f}%\033[0m\n"
        output += f"  Total Requests: {stats['total_requests']}\n"
        output += f"  Successful:     \033[32m{stats['successful']}\033[0m\n"
        output += f"  Failed:         \033[31m{stats['failed']}\033[0m\n"
        output += f"  Current VUs:    \033[36m{stats['current_vus']}\033[0m\n"
        output += f"  Avg Response:   {stats['avg_response']:.2f} ms\n"
        output += f"  Min Response:   \033[32m{stats['min_response']:.2f} ms\033[0m\n"
        output += f"  Max Response:   \033[33m{stats['max_response']:.2f} ms\033[0m\n"
        output += f"  P95 Response:   \033[33m{stats['p95_response']:.2f} ms\033[0m\n"
        output += f"  P99 Response:   \033[31m{stats['p99_response']:.2f} ms\033[0m\n"
        output += f"  Iterations:     \033[36m{stats['total_iterations']}\033[0m\n"
        
        return output
    
    def _create_progress_bar_basic(self, progress: float, width: int = 50) -> str:
        """Create a basic text progress bar"""
        filled = int(progress * width)
        bar = "█" * filled + "░" * (width - filled)
        percent = int(progress * 100)
        return f"[{bar}] {percent}%"
    
    def run(self, update_interval: float = 1.0):
        """Run the progress display"""
        if RICH_AVAILABLE:
            self._run_rich(update_interval)
        else:
            self._run_basic(update_interval)
    
    def _run_rich(self, update_interval: float):
        """Run with rich library"""
        try:
            # Wait for file to exist
            wait_count = 0
            while wait_count < 60 and not os.path.exists(self.json_file):
                time.sleep(0.5)
                wait_count += 1
            
            if not os.path.exists(self.json_file):
                if self.console:
                    self.console.print(f"[yellow]Warning: JSON file not found: {self.json_file}[/yellow]")
                return
            
            with Live(self._create_display_rich({}), refresh_per_second=1/update_interval, screen=True) as live:
                no_update_count = 0
                while True:
                    # Read new metrics
                    has_updates = self.parser.read_new_lines()
                    stats = self.parser.get_statistics()
                    
                    # Update display
                    live.update(self._create_display_rich(stats))
                    
                    # Check if test is complete (file stops growing)
                    time.sleep(update_interval)
                    
                    # Exit if file hasn't been updated in a while and we have some data
                    if stats['duration_seconds'] > 0:
                        if not has_updates:
                            no_update_count += 1
                            if no_update_count >= 3:  # No updates for 3 cycles
                                # Final update and exit
                                stats = self.parser.get_statistics()
                                live.update(self._create_display_rich(stats))
                                time.sleep(1)  # Show final state briefly
                                break
                        else:
                            no_update_count = 0
        except KeyboardInterrupt:
            pass
        except Exception as e:
            if self.console:
                self.console.print(f"[red]Error: {e}[/red]")
            else:
                sys.stderr.write(f"Error: {e}\n")
    
    def _run_basic(self, update_interval: float):
        """Run with basic ANSI codes"""
        try:
            # Wait for file to exist
            wait_count = 0
            while wait_count < 60 and not os.path.exists(self.json_file):
                time.sleep(0.5)
                wait_count += 1
            
            if not os.path.exists(self.json_file):
                sys.stderr.write(f"Warning: JSON file not found: {self.json_file}\n")
                return
            
            no_update_count = 0
            while True:
                # Read new metrics
                has_updates = self.parser.read_new_lines()
                stats = self.parser.get_statistics()
                
                # Update display
                display = self._create_display_basic(stats)
                sys.stdout.write(display)
                sys.stdout.flush()
                
                time.sleep(update_interval)
                
                # Exit if file hasn't been updated in a while
                if stats['duration_seconds'] > 0:
                    if not has_updates:
                        no_update_count += 1
                        if no_update_count >= 3:  # No updates for 3 cycles
                            # Final update
                            stats = self.parser.get_statistics()
                            display = self._create_display_basic(stats)
                            sys.stdout.write(display)
                            sys.stdout.flush()
                            time.sleep(1)  # Show final state briefly
                            break
                    else:
                        no_update_count = 0
        except KeyboardInterrupt:
            # Restore cursor on interrupt
            sys.stdout.write("\033[?25h")  # Show cursor
            sys.stdout.flush()
        except Exception as e:
            sys.stderr.write(f"Error: {e}\n")
            sys.stdout.write("\033[?25h")  # Show cursor
            sys.stdout.flush()


def main():
    parser = argparse.ArgumentParser(description='Display animated test progress')
    parser.add_argument('json_file', help='Path to k6 JSON output file')
    parser.add_argument('--api-name', required=True, help='API name being tested')
    parser.add_argument('--test-mode', required=True, choices=['smoke', 'full', 'saturation'], help='Test mode')
    parser.add_argument('--payload-size', default='default', help='Payload size')
    parser.add_argument('--update-interval', type=float, default=1.0, help='Update interval in seconds')
    
    args = parser.parse_args()
    
    if not os.path.exists(args.json_file):
        print(f"Error: JSON file not found: {args.json_file}", file=sys.stderr)
        sys.exit(1)
    
    display = TestProgressDisplay(
        args.json_file,
        args.api_name,
        args.test_mode,
        args.payload_size
    )
    
    display.run(args.update_interval)


if __name__ == '__main__':
    main()
