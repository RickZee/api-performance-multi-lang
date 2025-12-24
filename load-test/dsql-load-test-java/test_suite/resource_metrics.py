"""
Resource metrics collector for EC2 instance during test execution.
Collects CPU, RAM, disk I/O, and network metrics via SSM.
"""

import time
import json
import threading
from datetime import datetime
from typing import Dict, List, Optional
from pathlib import Path
import boto3
from botocore.config import Config as BotoConfig
from botocore.exceptions import ClientError, BotoCoreError

from test_suite.config import Config


class ResourceMetricsCollector:
    """Collect ongoing resource usage metrics from EC2 instance."""
    
    def __init__(self, config: Config, instance_id: str):
        self.config = config
        self.instance_id = instance_id
        self.metrics_interval = 5  # Collect every 5 seconds
        self.is_collecting = False
        self.collection_thread: Optional[threading.Thread] = None
        self.metrics_data: List[Dict] = []
        
        # Configure boto3
        boto_config = BotoConfig(
            read_timeout=30,
            connect_timeout=10,
            retries={'max_attempts': 3, 'mode': 'adaptive'}
        )
        self.ssm = boto3.client('ssm', region_name=config.region, config=boto_config)
    
    def _collect_single_metric_sample(self) -> Optional[Dict]:
        """Collect a single sample of resource metrics via SSM."""
        try:
            # Use a comprehensive command to collect all metrics at once
            commands = [
                # CPU metrics (from /proc/stat and top)
                "CPU_USER=$(grep '^cpu ' /proc/stat | awk '{print $2}')",
                "CPU_NICE=$(grep '^cpu ' /proc/stat | awk '{print $3}')",
                "CPU_SYSTEM=$(grep '^cpu ' /proc/stat | awk '{print $4}')",
                "CPU_IDLE=$(grep '^cpu ' /proc/stat | awk '{print $5}')",
                "CPU_IOWAIT=$(grep '^cpu ' /proc/stat | awk '{print $6}')",
                "CPU_TOTAL=$((CPU_USER + CPU_NICE + CPU_SYSTEM + CPU_IDLE + CPU_IOWAIT))",
                "CPU_USED=$((CPU_USER + CPU_NICE + CPU_SYSTEM))",
                # Memory metrics (from /proc/meminfo)
                "MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')",
                "MEM_FREE=$(grep MemFree /proc/meminfo | awk '{print $2}')",
                "MEM_AVAILABLE=$(grep MemAvailable /proc/meminfo | awk '{print $2}')",
                "MEM_BUFFERS=$(grep Buffers /proc/meminfo | awk '{print $2}')",
                "MEM_CACHED=$(grep '^Cached' /proc/meminfo | awk '{print $2}')",
                "MEM_USED=$((MEM_TOTAL - MEM_FREE - MEM_BUFFERS - MEM_CACHED))",
                # Disk I/O metrics (from /proc/diskstats for root device)
                "ROOT_DEVICE=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//')",
                "if [ -f /proc/diskstats ]; then",
                "  DISK_STATS=$(grep \"${ROOT_DEVICE} \" /proc/diskstats | head -1)",
                "  DISK_READS=$(echo $DISK_STATS | awk '{print $4}')",
                "  DISK_READ_SECTORS=$(echo $DISK_STATS | awk '{print $6}')",
                "  DISK_WRITES=$(echo $DISK_STATS | awk '{print $8}')",
                "  DISK_WRITE_SECTORS=$(echo $DISK_STATS | awk '{print $10}')",
                "else",
                "  DISK_READS=0",
                "  DISK_READ_SECTORS=0",
                "  DISK_WRITES=0",
                "  DISK_WRITE_SECTORS=0",
                "fi",
                # Network metrics (from /proc/net/dev)
                "NET_RX_BYTES=$(cat /proc/net/dev | grep -E '^\\s*eth0|^\\s*ens' | head -1 | awk '{print $2}')",
                "NET_RX_PACKETS=$(cat /proc/net/dev | grep -E '^\\s*eth0|^\\s*ens' | head -1 | awk '{print $3}')",
                "NET_TX_BYTES=$(cat /proc/net/dev | grep -E '^\\s*eth0|^\\s*ens' | head -1 | awk '{print $10}')",
                "NET_TX_PACKETS=$(cat /proc/net/dev | grep -E '^\\s*eth0|^\\s*ens' | head -1 | awk '{print $11}')",
                # Process-specific metrics (Java test process)
                "JAVA_PID=$(ps aux | grep 'java.*dsql-load-test' | grep -v grep | awk '{print $2}' | head -1)",
                "if [ -n \"$JAVA_PID\" ]; then",
                "  JAVA_CPU=$(ps -p $JAVA_PID -o %cpu= | tr -d ' ')",
                "  JAVA_MEM=$(ps -p $JAVA_PID -o %mem= | tr -d ' ')",
                "  JAVA_RSS=$(ps -p $JAVA_PID -o rss= | tr -d ' ')",
                "else",
                "  JAVA_CPU=0",
                "  JAVA_MEM=0",
                "  JAVA_RSS=0",
                "fi",
                # Output JSON
                "echo '{'",
                "\"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\",",
                "\"cpu\": {",
                "  \"user\": $CPU_USER,",
                "  \"nice\": $CPU_NICE,",
                "  \"system\": $CPU_SYSTEM,",
                "  \"idle\": $CPU_IDLE,",
                "  \"iowait\": $CPU_IOWAIT,",
                "  \"total\": $CPU_TOTAL,",
                "  \"used\": $CPU_USED",
                "},",
                "\"memory\": {",
                "  \"total_kb\": $MEM_TOTAL,",
                "  \"free_kb\": $MEM_FREE,",
                "  \"available_kb\": $MEM_AVAILABLE,",
                "  \"used_kb\": $MEM_USED,",
                "  \"buffers_kb\": $MEM_BUFFERS,",
                "  \"cached_kb\": $MEM_CACHED",
                "},",
                "\"disk\": {",
                "  \"reads\": $DISK_READS,",
                "  \"read_sectors\": $DISK_READ_SECTORS,",
                "  \"writes\": $DISK_WRITES,",
                "  \"write_sectors\": $DISK_WRITE_SECTORS",
                "},",
                "\"network\": {",
                "  \"rx_bytes\": ${NET_RX_BYTES:-0},",
                "  \"rx_packets\": ${NET_RX_PACKETS:-0},",
                "  \"tx_bytes\": ${NET_TX_BYTES:-0},",
                "  \"tx_packets\": ${NET_TX_PACKETS:-0}",
                "},",
                "\"java_process\": {",
                "  \"pid\": ${JAVA_PID:-0},",
                "  \"cpu_percent\": ${JAVA_CPU:-0},",
                "  \"mem_percent\": ${JAVA_MEM:-0},",
                "  \"rss_kb\": ${JAVA_RSS:-0}",
                "}",
                "}'"
            ]
            
            response = self.ssm.send_command(
                InstanceIds=[self.instance_id],
                DocumentName='AWS-RunShellScript',
                Parameters={'commands': commands},
                TimeoutSeconds=30
            )
            
            command_id = response['Command']['CommandId']
            
            # Wait for command completion
            max_wait = 30
            waited = 0
            while waited < max_wait:
                try:
                    invocation = self.ssm.get_command_invocation(
                        CommandId=command_id,
                        InstanceId=self.instance_id
                    )
                    
                    if invocation['Status'] in ['Success', 'Failed', 'Cancelled', 'TimedOut']:
                        if invocation['Status'] == 'Success':
                            stdout = invocation.get('StandardOutputContent', '').strip()
                            # Extract JSON from output (may have extra text)
                            try:
                                # Find JSON object in output
                                start = stdout.find('{')
                                end = stdout.rfind('}') + 1
                                if start >= 0 and end > start:
                                    json_str = stdout[start:end]
                                    metric = json.loads(json_str)
                                    return metric
                            except (json.JSONDecodeError, ValueError) as e:
                                # If JSON parsing fails, return None
                                return None
                        break
                    
                    time.sleep(1)
                    waited += 1
                except (ClientError, BotoCoreError):
                    time.sleep(1)
                    waited += 1
            
            return None
            
        except (ClientError, BotoCoreError, Exception) as e:
            # Silently fail - don't interrupt test execution
            return None
    
    def _collection_loop(self):
        """Background thread loop for collecting metrics."""
        while self.is_collecting:
            try:
                metric = self._collect_single_metric_sample()
                if metric:
                    self.metrics_data.append(metric)
                time.sleep(self.metrics_interval)
            except Exception:
                # Continue collecting even if one sample fails
                time.sleep(self.metrics_interval)
    
    def start_collection(self):
        """Start collecting metrics in background thread."""
        if self.is_collecting:
            return
        
        self.is_collecting = True
        self.metrics_data = []
        self.collection_thread = threading.Thread(target=self._collection_loop, daemon=True)
        self.collection_thread.start()
    
    def stop_collection(self) -> List[Dict]:
        """Stop collecting metrics and return collected data."""
        self.is_collecting = False
        if self.collection_thread:
            self.collection_thread.join(timeout=10)
        
        return self.metrics_data.copy()
    
    def get_summary_statistics(self, metrics: List[Dict]) -> Dict:
        """Calculate summary statistics from collected metrics."""
        if not metrics:
            return {}
        
        # CPU utilization (calculate from idle time)
        cpu_utilizations = []
        for m in metrics:
            cpu = m.get('cpu', {})
            if cpu.get('total', 0) > 0:
                used = cpu.get('used', 0)
                total = cpu.get('total', 0)
                util = (used / total) * 100 if total > 0 else 0
                cpu_utilizations.append(util)
        
        # Memory usage
        mem_used_pcts = []
        mem_used_kb = []
        for m in metrics:
            mem = m.get('memory', {})
            total = mem.get('total_kb', 0)
            used = mem.get('used_kb', 0)
            if total > 0:
                mem_used_pcts.append((used / total) * 100)
                mem_used_kb.append(used)
        
        # Disk I/O (calculate rates from first and last samples)
        disk_read_rate = 0
        disk_write_rate = 0
        if len(metrics) >= 2:
            try:
                first = metrics[0]
                last = metrics[-1]
                first_disk = first.get('disk', {})
                last_disk = last.get('disk', {})
                # Parse timestamps (handle both with and without Z)
                first_ts = first['timestamp'].replace('Z', '+00:00') if 'Z' in first['timestamp'] else first['timestamp']
                last_ts = last['timestamp'].replace('Z', '+00:00') if 'Z' in last['timestamp'] else last['timestamp']
                time_diff = (datetime.fromisoformat(last_ts) - datetime.fromisoformat(first_ts)).total_seconds()
                if time_diff > 0:
                    reads_diff = last_disk.get('reads', 0) - first_disk.get('reads', 0)
                    writes_diff = last_disk.get('writes', 0) - first_disk.get('writes', 0)
                    disk_read_rate = reads_diff / time_diff
                    disk_write_rate = writes_diff / time_diff
            except (KeyError, ValueError, TypeError):
                pass
        
        # Network I/O (calculate rates from first and last samples)
        net_rx_rate = 0
        net_tx_rate = 0
        if len(metrics) >= 2:
            try:
                first = metrics[0]
                last = metrics[-1]
                first_net = first.get('network', {})
                last_net = last.get('network', {})
                # Parse timestamps (handle both with and without Z)
                first_ts = first['timestamp'].replace('Z', '+00:00') if 'Z' in first['timestamp'] else first['timestamp']
                last_ts = last['timestamp'].replace('Z', '+00:00') if 'Z' in last['timestamp'] else last['timestamp']
                time_diff = (datetime.fromisoformat(last_ts) - datetime.fromisoformat(first_ts)).total_seconds()
                if time_diff > 0:
                    rx_diff = last_net.get('rx_bytes', 0) - first_net.get('rx_bytes', 0)
                    tx_diff = last_net.get('tx_bytes', 0) - first_net.get('tx_bytes', 0)
                    net_rx_rate = rx_diff / time_diff
                    net_tx_rate = tx_diff / time_diff
            except (KeyError, ValueError, TypeError):
                pass
        
        # Java process metrics
        java_cpu_pcts = []
        java_mem_pcts = []
        java_rss_kb = []
        for m in metrics:
            java = m.get('java_process', {})
            if java.get('pid', 0) > 0:
                java_cpu_pcts.append(java.get('cpu_percent', 0))
                java_mem_pcts.append(java.get('mem_percent', 0))
                java_rss_kb.append(java.get('rss_kb', 0))
        
        # Calculate collection duration
        collection_duration = 0
        if len(metrics) >= 2:
            try:
                first_ts = metrics[0]['timestamp'].replace('Z', '+00:00') if 'Z' in metrics[0]['timestamp'] else metrics[0]['timestamp']
                last_ts = metrics[-1]['timestamp'].replace('Z', '+00:00') if 'Z' in metrics[-1]['timestamp'] else metrics[-1]['timestamp']
                collection_duration = (datetime.fromisoformat(last_ts) - datetime.fromisoformat(first_ts)).total_seconds()
            except (KeyError, ValueError, TypeError):
                pass
        
        return {
            'collection_duration_seconds': collection_duration,
            'sample_count': len(metrics),
            'cpu': {
                'avg_utilization_percent': sum(cpu_utilizations) / len(cpu_utilizations) if cpu_utilizations else 0,
                'max_utilization_percent': max(cpu_utilizations) if cpu_utilizations else 0,
                'min_utilization_percent': min(cpu_utilizations) if cpu_utilizations else 0,
            },
            'memory': {
                'avg_used_percent': sum(mem_used_pcts) / len(mem_used_pcts) if mem_used_pcts else 0,
                'max_used_percent': max(mem_used_pcts) if mem_used_pcts else 0,
                'min_used_percent': min(mem_used_pcts) if mem_used_pcts else 0,
                'avg_used_kb': sum(mem_used_kb) / len(mem_used_kb) if mem_used_kb else 0,
                'max_used_kb': max(mem_used_kb) if mem_used_kb else 0,
            },
            'disk': {
                'avg_read_ops_per_sec': disk_read_rate,
                'avg_write_ops_per_sec': disk_write_rate,
            },
            'network': {
                'avg_rx_bytes_per_sec': net_rx_rate,
                'avg_tx_bytes_per_sec': net_tx_rate,
                'total_rx_bytes': metrics[-1].get('network', {}).get('rx_bytes', 0) - metrics[0].get('network', {}).get('rx_bytes', 0) if len(metrics) >= 2 else 0,
                'total_tx_bytes': metrics[-1].get('network', {}).get('tx_bytes', 0) - metrics[0].get('network', {}).get('tx_bytes', 0) if len(metrics) >= 2 else 0,
            },
            'java_process': {
                'avg_cpu_percent': sum(java_cpu_pcts) / len(java_cpu_pcts) if java_cpu_pcts else 0,
                'max_cpu_percent': max(java_cpu_pcts) if java_cpu_pcts else 0,
                'avg_mem_percent': sum(java_mem_pcts) / len(java_mem_pcts) if java_mem_pcts else 0,
                'max_mem_percent': max(java_mem_pcts) if java_mem_pcts else 0,
                'avg_rss_kb': sum(java_rss_kb) / len(java_rss_kb) if java_rss_kb else 0,
                'max_rss_kb': max(java_rss_kb) if java_rss_kb else 0,
            }
        }

