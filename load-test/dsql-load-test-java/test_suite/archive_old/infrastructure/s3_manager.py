"""
S3 upload/download operations.
"""

import boto3
from typing import Optional
from pathlib import Path
from botocore.exceptions import ClientError, BotoCoreError


class S3Manager:
    """Handle S3 operations."""
    
    def __init__(self, bucket_name: Optional[str], region: str):
        self.bucket_name = bucket_name
        self.region = region
        if bucket_name:
            self.s3 = boto3.client('s3', region_name=region)
        else:
            self.s3 = None
    
    def upload_file(self, local_path: str, s3_key: str) -> bool:
        """Upload a file to S3."""
        if not self.s3 or not self.bucket_name:
            return False
        
        try:
            self.s3.upload_file(local_path, self.bucket_name, s3_key)
            return True
        except (ClientError, BotoCoreError) as e:
            print(f"Error uploading to S3: {e}")
            return False
    
    def download_file(self, s3_key: str, local_path: str) -> bool:
        """Download a file from S3."""
        if not self.s3 or not self.bucket_name:
            return False
        
        try:
            # Ensure parent directory exists
            Path(local_path).parent.mkdir(parents=True, exist_ok=True)
            self.s3.download_file(self.bucket_name, s3_key, local_path)
            return True
        except (ClientError, BotoCoreError) as e:
            print(f"Error downloading from S3: {e}")
            return False
    
    def file_exists(self, s3_key: str) -> bool:
        """Check if a file exists in S3."""
        if not self.s3 or not self.bucket_name:
            return False
        
        try:
            self.s3.head_object(Bucket=self.bucket_name, Key=s3_key)
            return True
        except ClientError:
            return False
    
    def list_files(self, prefix: str) -> list[str]:
        """List files with a given prefix."""
        if not self.s3 or not self.bucket_name:
            return []
        
        try:
            response = self.s3.list_objects_v2(Bucket=self.bucket_name, Prefix=prefix)
            if 'Contents' in response:
                return [obj['Key'] for obj in response['Contents']]
            return []
        except (ClientError, BotoCoreError):
            return []

