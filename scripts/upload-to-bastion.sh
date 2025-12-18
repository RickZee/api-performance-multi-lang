#!/bin/bash
# Helper script to upload a file to bastion host via SSM
# Usage: upload-to-bastion.sh <file> <bastion_instance_id> <remote_path> <region>

set -e

FILE="$1"
BASTION_INSTANCE_ID="$2"
REMOTE_PATH="$3"
AWS_REGION="${4:-us-east-1}"

if [ ! -f "$FILE" ]; then
    echo "Error: File not found: $FILE" >&2
    exit 1
fi

# Use Python to handle large file uploads via SSM
python3 <<PYTHON_SCRIPT
import boto3
import base64
import sys
import json

file_path = "$FILE"
instance_id = "$BASTION_INSTANCE_ID"
remote_path = "$REMOTE_PATH"
region = "$AWS_REGION"

# Read and encode file
with open(file_path, 'rb') as f:
    file_content = f.read()
    file_b64 = base64.b64encode(file_content).decode('utf-8')

# Split into chunks to avoid command line limits
chunk_size = 50000
chunks = [file_b64[i:i+chunk_size] for i in range(0, len(file_b64), chunk_size)]

# Build commands to reconstruct file on bastion
commands = [
    f"mkdir -p $(dirname {remote_path})",
    f"cat > {remote_path}.b64 <<'FILE_EOF'"
]

# Add chunks
for chunk in chunks:
    commands.append(chunk)

commands.append("FILE_EOF")
commands.append(f"base64 -d < {remote_path}.b64 > {remote_path}")
commands.append(f"rm {remote_path}.b64")
commands.append(f"ls -lh {remote_path}")

# Send command
ssm = boto3.client('ssm', region_name=region)
response = ssm.send_command(
    InstanceIds=[instance_id],
    DocumentName='AWS-RunShellScript',
    Parameters={'commands': commands}
)

command_id = response['Command']['CommandId']
print(f"Upload command sent: {command_id}", file=sys.stderr)

# Wait for completion
import time
max_wait = 60
elapsed = 0
while elapsed < max_wait:
    time.sleep(2)
    elapsed += 2
    result = ssm.get_command_invocation(
        CommandId=command_id,
        InstanceId=instance_id
    )
    status = result['Status']
    if status in ['Success', 'Failed', 'Cancelled', 'TimedOut']:
        if status == 'Success':
            print(f"File uploaded successfully to {remote_path}", file=sys.stderr)
            sys.exit(0)
        else:
            print(f"Upload failed: {status}", file=sys.stderr)
            print(result.get('StandardErrorContent', ''), file=sys.stderr)
            sys.exit(1)

print("Upload timed out", file=sys.stderr)
sys.exit(1)
PYTHON_SCRIPT
