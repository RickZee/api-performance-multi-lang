#!/usr/bin/env python3
"""
Message verification script for Confluent Cloud topics
Consumes messages from topics and counts them
"""

import subprocess
import sys
import signal
import time
import json

def consume_messages(topic, max_seconds=3, max_messages=50):
    """Consume messages from a topic for a limited time using threading"""
    import threading
    
    count = 0
    process = None
    stop_flag = threading.Event()
    
    def reader():
        nonlocal count
        try:
            while not stop_flag.is_set():
                if process and process.poll() is not None:
                    break
                try:
                    line = process.stdout.readline()
                    if not line:
                        if stop_flag.is_set():
                            break
                        time.sleep(0.05)
                        continue
                    
                    line = line.strip()
                    if line and not line.startswith('Error') and not line.startswith('Usage') and not line.startswith('Consuming'):
                        count += 1
                        if count >= max_messages:
                            stop_flag.set()
                            break
                except:
                    break
        except:
            pass
    
    try:
        # Use confluent CLI to consume messages
        cmd = [
            'confluent', 'kafka', 'topic', 'consume', topic,
            '--from-beginning',
            '--value-format', 'string'
        ]
        
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=0
        )
        
        # Start reader thread
        reader_thread = threading.Thread(target=reader, daemon=True)
        reader_thread.start()
        
        # Wait for timeout or max messages
        start_time = time.time()
        while time.time() - start_time < max_seconds:
            if stop_flag.is_set() or count >= max_messages:
                break
            time.sleep(0.1)
        
        stop_flag.set()
        
        # Give thread a moment to finish
        reader_thread.join(timeout=0.5)
        
        return count
        
    except KeyboardInterrupt:
        stop_flag.set()
        return count
    except Exception as e:
        return -1
    finally:
        if process:
            try:
                process.terminate()
                time.sleep(0.3)
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=1)
            except:
                try:
                    process.kill()
                except:
                    pass
    
    return count

def main():
    if len(sys.argv) < 2:
        print("0")
        sys.exit(0)
    
    topic = sys.argv[1]
    max_seconds = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    max_messages = int(sys.argv[3]) if len(sys.argv) > 3 else 100
    
    count = consume_messages(topic, max_seconds, max_messages)
    print(count)
    sys.exit(0)

if __name__ == '__main__':
    main()
