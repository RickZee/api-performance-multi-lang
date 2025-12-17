"""Rich UI components for test runner."""

import time
from typing import Dict, List, Optional
from datetime import datetime, timedelta
from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.progress import Progress, BarColumn, TextColumn, TimeElapsedColumn, SpinnerColumn
from rich.layout import Layout
from rich.text import Text
from rich.live import Live
from rich import box


class TestRunnerUI:
    """UI components for test runner using Rich."""
    
    # Color mapping for each API - ensures each API has a unique color
    API_COLORS = {
        "producer-api-java-rest": "bright_blue",
        "producer-api-java-grpc": "bright_cyan",
        "producer-api-rust-rest": "bright_red",
        "producer-api-rust-grpc": "bright_magenta",
        "producer-api-go-rest": "bright_green",
        "producer-api-go-grpc": "bright_yellow",
        "producer-api-go-rest-lambda": "green",
        "producer-api-go-grpc-lambda": "yellow",
    }
    
    def __init__(self, console: Optional[Console] = None):
        self.console = console or Console()
        self.start_time = time.time()
    
    @classmethod
    def get_api_color(cls, api_name: str) -> str:
        """Get color for an API name."""
        return cls.API_COLORS.get(api_name, "white")
    
    @classmethod
    def format_api_name(cls, api_name: str) -> str:
        """Format API name with its assigned color."""
        color = cls.get_api_color(api_name)
        return f"[{color}]{api_name}[/{color}]"
    
    def create_header_panel(self, test_mode: str, api_count: int, payload_sizes: List[str]) -> Panel:
        """Create header panel with test configuration."""
        payload_str = ", ".join(payload_sizes) if payload_sizes else "400b"
        header_text = f"[bold blue]Test Mode:[/bold blue] {test_mode.upper()} | "
        header_text += f"[bold blue]APIs:[/bold blue] {api_count} | "
        header_text += f"[bold blue]Payload Sizes:[/bold blue] {payload_str}"
        return Panel(header_text, border_style="blue", title="Test Configuration")
    
    def create_progress_panel(self, current: int, total: int, current_test: Optional[str] = None) -> Layout:
        """Create progress panel showing overall test progress with title above."""
        progress_table = Table.grid(padding=1)
        progress_table.add_column(style="cyan", width=20)
        progress_table.add_column(style="white")
        
        # Overall progress bar
        progress_pct = (current / total * 100) if total > 0 else 0
        progress_bar = self._create_progress_bar(progress_pct / 100)
        progress_table.add_row("Overall Progress:", progress_bar)
        
        # Current test info
        if current_test:
            progress_table.add_row("Current Test:", f"[cyan]{current_test}[/cyan]")
        
        # Elapsed time
        elapsed = time.time() - self.start_time
        elapsed_str = self._format_duration(elapsed)
        progress_table.add_row("Elapsed Time:", f"[green]{elapsed_str}[/green]")
        
        # Create a layout with title above the panel
        progress_layout = Layout()
        progress_layout.split_column(
            Layout(Text("Progress", style="bold"), size=1, name="title"),
            Layout(Panel(progress_table, border_style="green"), name="content")
        )
        
        return progress_layout
    
    def create_status_panel(self, api_name: str, payload_size: str, status: str, 
                           phase: Optional[Dict] = None, metrics: Optional[Dict] = None) -> Panel:
        """Create status panel for current test."""
        status_table = Table.grid(padding=1)
        status_table.add_column(style="cyan", width=25)
        status_table.add_column(style="white", width=30)
        
        # Use API-specific color
        status_table.add_row("API:", f"[bold]{self.format_api_name(api_name)}[/bold]")
        status_table.add_row("Payload Size:", payload_size)
        
        # Status with color
        status_color = {
            "running": "yellow",
            "completed": "green",
            "failed": "red",
            "waiting": "cyan",
            "skipped": "dim",
        }.get(status.lower(), "white")
        status_table.add_row("Status:", f"[{status_color}]{status.upper()}[/{status_color}]")
        
        # Phase information
        if phase:
            phase_text = f"Phase {phase['num']}: {phase['name']} ({phase['vus']} VUs)"
            status_table.add_row("Current Phase:", f"[cyan]{phase_text}[/cyan]")
        
        # Metrics
        if metrics:
            status_table.add_row("", "")  # Spacer
            status_table.add_row("[bold]Metrics:[/bold]", "")
            status_table.add_row("  Throughput:", f"{metrics.get('throughput', 0):.2f} req/s")
            status_table.add_row("  Avg Response:", f"{metrics.get('avg_response', 0):.2f} ms")
            status_table.add_row("  P95 Response:", f"{metrics.get('p95_response', 0):.2f} ms")
            status_table.add_row("  Error Rate:", f"{metrics.get('error_rate', 0):.2f}%")
        
        return Panel(status_table, title="Current Test Status", border_style="yellow")
    
    def create_results_table(self, results: List[Dict]) -> Table:
        """Create results summary table."""
        table = Table(title="Test Results Summary", box=box.ROUNDED)
        table.add_column("API", style="cyan", no_wrap=True)
        table.add_column("Payload", style="white")
        table.add_column("Status", justify="center")
        table.add_column("Throughput", justify="right", style="green")
        table.add_column("Avg (ms)", justify="right")
        table.add_column("P95 (ms)", justify="right")
        table.add_column("P99 (ms)", justify="right")
        table.add_column("Error %", justify="right")
        
        for result in results:
            status = result.get('status', 'unknown')
            status_icon = {
                'completed': '[green]✓[/green]',
                'failed': '[red]✗[/red]',
                'running': '[yellow]⟳[/yellow]',
                'skipped': '[dim]-[/dim]',
            }.get(status.lower(), '?')
            
            # Use API-specific color for API name
            api_name = result.get('api_name', '')
            formatted_api_name = self.format_api_name(api_name)
            
            metrics = result.get('metrics', {})
            table.add_row(
                formatted_api_name,
                result.get('payload_size', '400b'),
                status_icon,
                f"{metrics.get('throughput', 0):.2f}",
                f"{metrics.get('avg_response', 0):.2f}",
                f"{metrics.get('p95_response', 0):.2f}",
                f"{metrics.get('p99_response', 0):.2f}",
                f"{metrics.get('error_rate', 0):.2f}%",
            )
        
        return table
    
    def create_dashboard_layout(self, header: Panel, progress: Layout, status: Panel, 
                               results: Optional[Table] = None) -> Layout:
        """Create main dashboard layout."""
        layout = Layout()
        
        layout.split_column(
            Layout(header, size=3, name="header"),
            Layout(name="main"),
        )
        
        layout["main"].split_row(
            Layout(name="left"),
            Layout(name="right"),
        )
        
        # Progress is now a Layout with title, so we need to account for that
        layout["left"].split_column(
            Layout(progress, size=7, name="progress"),  # Increased size to account for title
            Layout(status, name="status"),
        )
        
        if results:
            layout["right"].update(results)
        else:
            layout["right"].update(Panel("Results will appear here", title="Results", border_style="dim"))
        
        return layout
    
    def _create_progress_bar(self, progress: float, width: int = 50) -> str:
        """Create a text progress bar."""
        filled = int(progress * width)
        bar = "█" * filled + "░" * (width - filled)
        percent = int(progress * 100)
        color = "green" if percent >= 90 else "yellow" if percent >= 50 else "cyan"
        return f"[{color}]{bar}[/{color}] {percent}%"
    
    def _format_duration(self, seconds: float) -> str:
        """Format duration as HH:MM:SS or MM:SS."""
        if seconds < 3600:
            m = int(seconds // 60)
            s = int(seconds % 60)
            return f"{m:02d}:{s:02d}"
        else:
            h = int(seconds // 3600)
            m = int((seconds % 3600) // 60)
            s = int(seconds % 60)
            return f"{h:02d}:{m:02d}:{s:02d}"
    
    def print_error(self, message: str):
        """Print error message."""
        self.console.print(f"[red]✗ Error:[/red] {message}")
    
    def print_success(self, message: str):
        """Print success message."""
        self.console.print(f"[green]✓[/green] {message}")
    
    def print_warning(self, message: str):
        """Print warning message."""
        self.console.print(f"[yellow]⚠[/yellow] {message}")
    
    def print_info(self, message: str):
        """Print info message."""
        self.console.print(f"[cyan]ℹ[/cyan] {message}")
