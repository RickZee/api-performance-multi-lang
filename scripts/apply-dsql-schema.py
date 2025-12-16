import boto3
import json
import os
import sys
import time

def main():
    # Configuration
    BASTION_ID = "i-0adcbf0f85849149e"
    DSQL_HOST = "vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws"
    AWS_REGION = "us-east-1"
    SCHEMA_FILE = "data/schema-dsql.sql"

    # Read schema file
    try:
        with open(SCHEMA_FILE, "r") as f:
            schema_sql = f.read()
    except FileNotFoundError:
        print(f"Error: Schema file '{SCHEMA_FILE}' not found.")
        return 1

    print(f"Read {len(schema_sql)} bytes from {SCHEMA_FILE}")

    # Construct the shell script to run on the bastion
    # We use a simple approach: write SQL to a file, then run psql
    
    # Escape single quotes for the shell command inside JSON
    # But since we use python boto3, we just need to pass the string.
    # However, sending it as a parameter to SSM requires some care if passing as string argument.
    # A safer way allows writing to a file using cat.
    
    # We will create a small script on the bastion
    
    commands = [
        f"cat <<'HEREDOC' > /tmp/schema.sql\n{schema_sql}\nHEREDOC",
        f"export DSQL_HOST={DSQL_HOST}",
        f"export AWS_REGION={AWS_REGION}",
        "TOKEN=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST)",
        "export PGPASSWORD=$TOKEN",
        # Use -f to run from file
        f"psql -h $DSQL_HOST -U admin -d postgres -p 5432 -f /tmp/schema.sql"
    ]

    print("Sending command to bastion via SSM...")
    
    ssm = boto3.client("ssm", region_name=AWS_REGION)
    
    response = ssm.send_command(
        InstanceIds=[BASTION_ID],
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": commands}
    )
    
    command_id = response["Command"]["CommandId"]
    print(f"Command ID: {command_id}")
    
    # Wait for completion
    print("Waiting for completion...")
    while True:
        time.sleep(2)
        invocation = ssm.get_command_invocation(
            CommandId=command_id,
            InstanceId=BASTION_ID
        )
        status = invocation["Status"]
        
        if status in ["Pending", "InProgress", "Delayed"]:
            continue
            
        print(f"Status: {status}")
        
        if status == "Success":
            print("Output:")
            print(invocation.get("StandardOutputContent", ""))
        else:
            print("Error Output:")
            print(invocation.get("StandardErrorContent", ""))
            print(invocation.get("StatusDetails", ""))
            return 1
        
        break
        
    return 0

if __name__ == "__main__":
    sys.exit(main())
