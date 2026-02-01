#!/usr/bin/env python3
"""
OpenClaw Storage MCP Server
Free, open-source AI data management with natural language interface
No enterprise licenses required - uses AIStor Free + rclone
"""

import asyncio
import json
import os
import sys
import subprocess
from pathlib import Path
from datetime import datetime
import argparse


class OpenClawStorageMCP:
    def __init__(self):
        self.aistor_endpoint = os.getenv("AISTOR_ENDPOINT", "http://10.1.1.120:9000")
        self.buckets = {
            "models": os.getenv("BUCKET_MODELS", "ai-models"),
            "datasets": os.getenv("BUCKET_DATASETS", "training-data"),
            "experiments": os.getenv("BUCKET_EXPERIMENTS", "experiments"),
            "logs": os.getenv("BUCKET_LOGS", "ai-logs"),
            "cache": os.getenv("BUCKET_CACHE", "nix-cache"),
        }
        self.state_dir = Path("/var/lib/openclaw-storage")
        self.state_dir.mkdir(exist_ok=True)

    async def handle_command(self, command: str, params: dict) -> dict:
        handlers = {
            "store_model": self.store_model,
            "store_dataset": self.store_dataset,
            "store_experiment": self.store_experiment,
            "list_models": self.list_models,
            "list_datasets": self.list_datasets,
            "list_experiments": self.list_experiments,
            "get_storage_stats": self.get_storage_stats,
            "backup_to_cloud": self.backup_to_cloud,
            "sync_from_cloud": self.sync_from_cloud,
            "natural_language": self.natural_language_handler,
        }

        handler = handlers.get(command)
        if handler:
            return await handler(params)
        return {"error": f"Unknown command: {command}"}

    async def natural_language_handler(self, params: dict) -> dict:
        query = params.get("query", "").lower()

        # Parse natural language queries
        if "store" in query and ("model" in query or "checkpoint" in query):
            return await self.store_model(params)
        elif "store" in query and "dataset" in query:
            return await self.store_dataset(params)
        elif "store" in query and "experiment" in query:
            return await self.store_experiment(params)
        elif "list" in query and "model" in query:
            return await self.list_models(params)
        elif "list" in query and "dataset" in query:
            return await self.list_datasets(params)
        elif "list" in query and "experiment" in query:
            return await self.list_experiments(params)
        elif "storage" in query and ("stats" in query or "usage" in query):
            return await self.get_storage_stats(params)
        elif "backup" in query:
            return await self.backup_to_cloud(params)
        elif "sync" in query or "download" in query:
            return await self.sync_from_cloud(params)
        else:
            return {
                "error": "Could not understand query",
                "query": query,
                "available_commands": [
                    "store_model",
                    "store_dataset",
                    "store_experiment",
                    "list_models",
                    "list_datasets",
                    "list_experiments",
                    "get_storage_stats",
                    "backup_to_cloud",
                    "sync_from_cloud",
                ],
            }

    async def store_model(self, params: dict) -> dict:
        local_path = params.get("local_path")
        model_name = params.get("model_name", "unnamed")
        run_id = params.get("run_id", datetime.now().strftime("%Y%m%d-%H%M%S"))

        if not local_path:
            return {"error": "local_path required"}

        remote_path = f"{run_id}/{model_name}"
        bucket = self.buckets["models"]

        # Use mc to upload
        cmd = ["mc", "cp", local_path, f"aistor/{bucket}/{remote_path}"]
        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode == 0:
            return {
                "success": True,
                "message": f"Model stored: {bucket}/{remote_path}",
                "bucket": bucket,
                "path": remote_path,
                "endpoint": self.aistor_endpoint,
            }
        return {"error": result.stderr}

    async def store_dataset(self, params: dict) -> dict:
        local_path = params.get("local_path")
        dataset_name = params.get("dataset_name", "unnamed")

        if not local_path:
            return {"error": "local_path required"}

        bucket = self.buckets["datasets"]
        remote_path = f"{dataset_name}/{Path(local_path).name}"

        cmd = ["mc", "cp", "-r", local_path, f"aistor/{bucket}/{remote_path}"]
        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode == 0:
            return {
                "success": True,
                "message": f"Dataset stored: {bucket}/{remote_path}",
                "bucket": bucket,
                "path": remote_path,
            }
        return {"error": result.stderr}

    async def store_experiment(self, params: dict) -> dict:
        experiment_id = params.get(
            "experiment_id", datetime.now().strftime("%Y%m%d-%H%M%S")
        )
        artifacts_path = params.get("artifacts_path")
        metrics = params.get("metrics", {})

        bucket = self.buckets["experiments"]

        # Store metrics as JSON
        metrics_file = self.state_dir / f"{experiment_id}-metrics.json"
        metrics_file.write_text(json.dumps(metrics, indent=2))

        cmd = [
            "mc",
            "cp",
            str(metrics_file),
            f"aistor/{bucket}/{experiment_id}/metrics.json",
        ]
        subprocess.run(cmd, capture_output=True)

        # Store artifacts if provided
        if artifacts_path:
            cmd = [
                "mc",
                "cp",
                "-r",
                artifacts_path,
                f"aistor/{bucket}/{experiment_id}/artifacts/",
            ]
            subprocess.run(cmd, capture_output=True)

        return {
            "success": True,
            "message": f"Experiment stored: {experiment_id}",
            "experiment_id": experiment_id,
            "bucket": bucket,
        }

    async def list_models(self, params: dict) -> dict:
        bucket = self.buckets["models"]
        prefix = params.get("prefix", "")

        cmd = ["mc", "ls", "--recursive", f"aistor/{bucket}/{prefix}"]
        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode == 0:
            lines = result.stdout.strip().split("\n")
            models = [line.split()[-1] for line in lines if line.strip()]
            return {"success": True, "models": models, "count": len(models)}
        return {"error": result.stderr}

    async def list_datasets(self, params: dict) -> dict:
        bucket = self.buckets["datasets"]
        cmd = ["mc", "ls", "--recursive", f"aistor/{bucket}/"]
        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode == 0:
            lines = result.stdout.strip().split("\n")
            datasets = [line.split()[-1] for line in lines if line.strip()]
            return {"success": True, "datasets": datasets, "count": len(datasets)}
        return {"error": result.stderr}

    async def list_experiments(self, params: dict) -> dict:
        bucket = self.buckets["experiments"]
        cmd = ["mc", "ls", f"aistor/{bucket}/"]
        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode == 0:
            lines = result.stdout.strip().split("\n")
            experiments = [
                line.split()[-1].rstrip("/") for line in lines if line.strip()
            ]
            return {
                "success": True,
                "experiments": experiments,
                "count": len(experiments),
            }
        return {"error": result.stderr}

    async def get_storage_stats(self, params: dict) -> dict:
        stats = {}
        total_size = 0
        total_objects = 0

        for bucket_type, bucket_name in self.buckets.items():
            cmd = ["mc", "du", f"aistor/{bucket_name}/"]
            result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode == 0:
                # Parse du output
                lines = result.stdout.strip().split("\n")
                for line in lines:
                    if "Total" in line:
                        parts = line.split()
                        if len(parts) >= 2:
                            size_str = parts[0]
                            stats[bucket_type] = size_str

        return {
            "success": True,
            "stats": stats,
            "endpoint": self.aistor_endpoint,
            "buckets": self.buckets,
        }

    async def backup_to_cloud(self, params: dict) -> dict:
        bucket_type = params.get("bucket_type", "models")
        cloud_remote = params.get("cloud_remote", "gdrive")

        bucket = self.buckets.get(bucket_type, bucket_type)

        # Use rclone to sync to cloud
        cmd = [
            "rclone",
            "sync",
            f":s3:{bucket}",
            f"{cloud_remote}:openclaw-{bucket_type}-backup",
            "--s3-endpoint",
            self.aistor_endpoint,
            "--s3-region",
            "us-east-1",
            "--progress",
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode == 0:
            return {
                "success": True,
                "message": f"Backed up {bucket} to {cloud_remote}",
                "bucket": bucket,
                "cloud_remote": cloud_remote,
            }
        return {"error": result.stderr}

    async def sync_from_cloud(self, params: dict) -> dict:
        cloud_remote = params.get("cloud_remote", "gdrive")
        cloud_path = params.get("cloud_path", "openclaw-backup")
        local_bucket = params.get("local_bucket", "models")

        bucket = self.buckets.get(local_bucket, local_bucket)

        cmd = [
            "rclone",
            "sync",
            f"{cloud_remote}:{cloud_path}",
            f":s3:{bucket}",
            "--s3-endpoint",
            self.aistor_endpoint,
            "--s3-region",
            "us-east-1",
            "--progress",
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode == 0:
            return {
                "success": True,
                "message": f"Synced {cloud_remote}:{cloud_path} to {bucket}",
                "source": f"{cloud_remote}:{cloud_path}",
                "destination": bucket,
            }
        return {"error": result.stderr}


async def main():
    parser = argparse.ArgumentParser(description="OpenClaw Storage MCP Server")
    parser.add_argument("--port", type=int, default=18800, help="Server port")
    parser.add_argument("--command", "-c", help="Single command to execute")
    parser.add_argument("--params", "-p", help="JSON params for command")
    args = parser.parse_args()

    mcp = OpenClawStorageMCP()

    if args.command:
        # Single command mode
        params = json.loads(args.params) if args.params else {}
        result = await mcp.handle_command(args.command, params)
        print(json.dumps(result, indent=2))
    else:
        # Server mode - read commands from stdin
        print(f"OpenClaw Storage MCP Server ready on port {args.port}")
        print(
            "Commands: store_model, store_dataset, store_experiment, list_models, list_datasets, list_experiments, get_storage_stats, backup_to_cloud, sync_from_cloud"
        )
        print(
            "Natural language: 'store model from /path/to/model', 'list all experiments', 'backup models to gdrive'"
        )

        while True:
            try:
                line = input()
                data = json.loads(line)
                command = data.get("command")
                params = data.get("params", {})

                result = await mcp.handle_command(command, params)
                print(json.dumps(result))
                sys.stdout.flush()
            except EOFError:
                break
            except json.JSONDecodeError as e:
                print(json.dumps({"error": f"Invalid JSON: {e}"}))
                sys.stdout.flush()
            except Exception as e:
                print(json.dumps({"error": str(e)}))
                sys.stdout.flush()


if __name__ == "__main__":
    asyncio.run(main())
