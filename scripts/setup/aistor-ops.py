#!/usr/bin/env python3
"""
AIStor Natural Language Interface for AI Operations
Translates natural language to S3 operations for AIStor
"""

import boto3
import sys
import json
from pathlib import Path


class AIStorOps:
    def __init__(
        self, endpoint="http://10.1.1.120:9000", access_key=None, secret_key=None
    ):
        self.s3 = boto3.client(
            "s3",
            endpoint_url=endpoint,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            region_name="us-east-1",
        )
        self.endpoint = endpoint

    def create_bucket(self, name):
        """Create a new bucket"""
        try:
            self.s3.create_bucket(Bucket=name)
            return f"Created bucket: {name}"
        except Exception as e:
            return f"Error: {e}"

    def list_buckets(self):
        """List all buckets"""
        response = self.s3.list_buckets()
        buckets = [b["Name"] for b in response["Buckets"]]
        return f"Buckets: {', '.join(buckets)}"

    def upload_file(self, bucket, local_path, remote_key):
        """Upload file to bucket"""
        try:
            self.s3.upload_file(local_path, bucket, remote_key)
            return f"Uploaded {local_path} to {bucket}/{remote_key}"
        except Exception as e:
            return f"Error: {e}"

    def list_objects(self, bucket, prefix=""):
        """List objects in bucket"""
        try:
            response = self.s3.list_objects_v2(Bucket=bucket, Prefix=prefix)
            objects = [obj["Key"] for obj in response.get("Contents", [])]
            return f"Objects in {bucket}: {', '.join(objects[:20])}"
        except Exception as e:
            return f"Error: {e}"

    def get_storage_stats(self):
        """Get storage statistics across all buckets"""
        try:
            total_size = 0
            total_objects = 0
            buckets = self.s3.list_buckets()["Buckets"]

            for bucket in buckets:
                bucket_name = bucket["Name"]
                try:
                    response = self.s3.list_objects_v2(Bucket=bucket_name)
                    for obj in response.get("Contents", []):
                        total_size += obj["Size"]
                        total_objects += 1
                except:
                    pass

            size_gb = total_size / (1024**3)
            return f"Total: {size_gb:.2f} GB across {total_objects} objects in {len(buckets)} buckets"
        except Exception as e:
            return f"Error: {e}"


def main():
    import argparse

    parser = argparse.ArgumentParser(description="AIStor Natural Language Interface")
    parser.add_argument(
        "--command", "-c", required=True, help="Natural language command"
    )
    parser.add_argument(
        "--endpoint", default="http://10.1.1.120:9000", help="AIStor endpoint"
    )
    parser.add_argument("--access-key", default=None, help="Access key")
    parser.add_argument("--secret-key", default=None, help="Secret key")

    args = parser.parse_args()

    # Load credentials from environment or secrets
    access_key = (
        args.access_key
        or Path("/run/agenix/aistor-credentials")
        .read_text()
        .split("\n")[0]
        .split("=")[1]
    )
    secret_key = (
        args.secret_key
        or Path("/run/agenix/aistor-credentials")
        .read_text()
        .split("\n")[1]
        .split("=")[1]
    )

    aistor = AIStorOps(args.endpoint, access_key, secret_key)

    # Parse natural language command
    cmd = args.command.lower()

    if "create bucket" in cmd or "make bucket" in cmd:
        bucket = cmd.split("bucket")[-1].strip().split()[0]
        print(aistor.create_bucket(bucket))
    elif "list buckets" in cmd or "show buckets" in cmd:
        print(aistor.list_buckets())
    elif "upload" in cmd:
        # Parse: "upload file.txt to bucket/path"
        parts = cmd.split()
        print(f"Upload command parsed: {parts}")
    elif "storage stats" in cmd or "show storage" in cmd:
        print(aistor.get_storage_stats())
    else:
        print(f"Unknown command: {cmd}")
        print("Available: create bucket, list buckets, storage stats, upload")


if __name__ == "__main__":
    main()
