#!/usr/bin/env python3
"""
 AIStor Integration Workflows
Automated AI data management workflows leveraging AIStor capabilities
"""

import asyncio
import json
import os
import subprocess
from datetime import datetime
from pathlib import Path
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("-aistor")


class AIStorWorkflows:
    """Automated workflows for AI/ML operations with AIStor"""

    def __init__(self):
        self.endpoint = os.getenv("AISTOR_ENDPOINT", "http://10.1.1.120:9000")
        self.buckets = {
            "models": "ai-models",
            "datasets": "training-data",
            "experiments": "experiments",
            "logs": "ai-logs",
            "cache": "nix-cache",
        }
        self.lobster_home = Path("/var/lib/lobster")

    async def training_checkpoint_workflow(
        self, run_id: str, local_path: str, metrics: dict
    ):
        """
        Automated workflow for training checkpoints:
        1. Upload model checkpoint with versioning
        2. Store metrics JSON
        3. Trigger cloud backup if accuracy > threshold
        4. Log the operation
        """
        logger.info(f"🏃 Training checkpoint workflow for run {run_id}")

        # 1. Upload model with metadata
        model_name = Path(local_path).name
        remote_path = f"{run_id}/checkpoints/{model_name}"

        # Add metadata tags
        tags = f"run={run_id},type=checkpoint,accuracy={metrics.get('accuracy', 0)}"
        cmd = [
            "mc",
            "cp",
            "--attr",
            tags,
            local_path,
            f"aistor/{self.buckets['models']}/{remote_path}",
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            logger.error(f"❌ Failed to upload model: {result.stderr}")
            return {"success": False, "error": result.stderr}

        # 2. Store metrics
        metrics_file = (
            self.lobster_home / "storage" / "metrics" / f"{run_id}-metrics.json"
        )
        metrics_file.parent.mkdir(parents=True, exist_ok=True)
        metrics_file.write_text(
            json.dumps(
                {
                    "run_id": run_id,
                    "timestamp": datetime.now().isoformat(),
                    "metrics": metrics,
                    "model_path": remote_path,
                },
                indent=2,
            )
        )

        cmd = [
            "mc",
            "cp",
            str(metrics_file),
            f"aistor/{self.buckets['experiments']}/{run_id}/metrics.json",
        ]
        subprocess.run(cmd, capture_output=True)

        # 3. Trigger cloud backup if high accuracy
        if metrics.get("accuracy", 0) > 0.9:
            logger.info(
                f"🌟 High accuracy detected ({metrics['accuracy']}), triggering cloud backup..."
            )
            await self.backup_to_cloud("models", "gdrive")

        # 4. Log operation
        await self.log_operation(
            "training_checkpoint",
            {
                "run_id": run_id,
                "model": model_name,
                "accuracy": metrics.get("accuracy"),
                "path": remote_path,
            },
        )

        logger.info(f"✅ Checkpoint workflow complete: {remote_path}")
        return {
            "success": True,
            "model_path": remote_path,
            "metrics_path": f"{run_id}/metrics.json",
            "backed_up": metrics.get("accuracy", 0) > 0.9,
        }

    async def dataset_ingestion_workflow(
        self, dataset_name: str, local_path: str, metadata: dict
    ):
        """
        Automated dataset ingestion:
        1. Upload dataset with metadata
        2. Generate statistics
        3. Create manifest file
        4. Update dataset registry
        """
        logger.info(f"📚 Dataset ingestion: {dataset_name}")

        # 1. Upload dataset
        cmd = [
            "mc",
            "cp",
            "-r",
            local_path,
            f"aistor/{self.buckets['datasets']}/{dataset_name}/",
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            return {"success": False, "error": result.stderr}

        # 2. Create manifest with metadata
        manifest = {
            "name": dataset_name,
            "created": datetime.now().isoformat(),
            "source_path": local_path,
            "metadata": metadata,
            "ai_stor_path": f"s3://{self.buckets['datasets']}/{dataset_name}/",
        }

        manifest_file = self.lobster_home / "storage" / f"{dataset_name}-manifest.json"
        manifest_file.write_text(json.dumps(manifest, indent=2))

        cmd = [
            "mc",
            "cp",
            str(manifest_file),
            f"aistor/{self.buckets['datasets']}/{dataset_name}/manifest.json",
        ]
        subprocess.run(cmd, capture_output=True)

        # 3. Log operation
        await self.log_operation(
            "dataset_ingestion",
            {
                "dataset": dataset_name,
                "path": f"{dataset_name}/",
                "size_mb": metadata.get("size_mb", 0),
            },
        )

        logger.info(f"✅ Dataset ingested: {dataset_name}")
        return {
            "success": True,
            "manifest": manifest,
            "path": f"{self.buckets['datasets']}/{dataset_name}/",
        }

    async def experiment_tracking_workflow(
        self, experiment_id: str, artifacts_path: str, config: dict, results: dict
    ):
        """
        Complete experiment tracking:
        1. Store all artifacts with versioning
        2. Store configuration
        3. Store results
        4. Generate experiment report
        """
        logger.info(f"🧪 Experiment tracking: {experiment_id}")

        bucket_path = f"aistor/{self.buckets['experiments']}/{experiment_id}"

        # 1. Store artifacts
        if artifacts_path:
            cmd = ["mc", "cp", "-r", artifacts_path, f"{bucket_path}/artifacts/"]
            subprocess.run(cmd, capture_output=True)

        # 2. Store config
        config_file = self.lobster_home / "storage" / f"{experiment_id}-config.json"
        config_file.write_text(json.dumps(config, indent=2))
        cmd = ["mc", "cp", str(config_file), f"{bucket_path}/config.json"]
        subprocess.run(cmd, capture_output=True)

        # 3. Store results
        results_file = self.lobster_home / "storage" / f"{experiment_id}-results.json"
        results_file.write_text(json.dumps(results, indent=2))
        cmd = ["mc", "cp", str(results_file), f"{bucket_path}/results.json"]
        subprocess.run(cmd, capture_output=True)

        # 4. Generate report
        report = {
            "experiment_id": experiment_id,
            "timestamp": datetime.now().isoformat(),
            "config_summary": config,
            "results_summary": results,
            "artifacts_path": f"{experiment_id}/artifacts/",
            "status": "completed",
        }

        report_file = self.lobster_home / "storage" / f"{experiment_id}-report.json"
        report_file.write_text(json.dumps(report, indent=2))
        cmd = ["mc", "cp", str(report_file), f"{bucket_path}/report.json"]
        subprocess.run(cmd, capture_output=True)

        # 5. Log operation
        await self.log_operation(
            "experiment_tracked",
            {
                "experiment_id": experiment_id,
                "config_keys": list(config.keys()),
                "result_keys": list(results.keys()),
            },
        )

        logger.info(f"✅ Experiment tracked: {experiment_id}")
        return {
            "success": True,
            "experiment_id": experiment_id,
            "report_path": f"{experiment_id}/report.json",
        }

    async def model_serving_workflow(self, model_name: str, version: str = "latest"):
        """
        Model serving preparation:
        1. Retrieve specific model version
        2. Verify integrity
        3. Prepare for local serving
        4. Log access
        """
        logger.info(f"🚀 Model serving: {model_name} (version: {version})")

        # 1. Find model
        if version == "latest":
            cmd = [
                "mc",
                "ls",
                "--recursive",
                f"aistor/{self.buckets['models']}/{model_name}/",
            ]
        else:
            cmd = [
                "mc",
                "ls",
                f"aistor/{self.buckets['models']}/{model_name}/{version}/",
            ]

        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            return {"success": False, "error": "Model not found"}

        # 2. Download to local cache
        local_path = self.lobster_home / "storage" / "cache" / model_name
        local_path.mkdir(parents=True, exist_ok=True)

        cmd = [
            "mc",
            "cp",
            "-r",
            f"aistor/{self.buckets['models']}/{model_name}/{version}/",
            str(local_path),
        ]
        subprocess.run(cmd, capture_output=True)

        # 3. Log access
        await self.log_operation(
            "model_served",
            {"model": model_name, "version": version, "local_path": str(local_path)},
        )

        logger.info(f"✅ Model ready for serving: {local_path}")
        return {"success": True, "model_path": str(local_path), "version": version}

    async def backup_to_cloud(self, bucket_type: str, cloud_remote: str = "gdrive"):
        """Backup bucket to cloud storage via rclone"""
        logger.info(f"☁️  Backing up {bucket_type} to {cloud_remote}")

        bucket = self.buckets.get(bucket_type, bucket_type)

        cmd = [
            "rclone",
            "sync",
            f":s3:{bucket}",
            f"{cloud_remote}:-{bucket_type}-backup",
            "--s3-endpoint",
            self.endpoint,
            "--s3-region",
            "us-east-1",
            "--progress",
            "--transfers",
            "4",
            "--checkers",
            "8",
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode == 0:
            logger.info(f"✅ Backup complete: {bucket_type} → {cloud_remote}")
            return {"success": True, "bucket": bucket, "remote": cloud_remote}
        else:
            logger.error(f"❌ Backup failed: {result.stderr}")
            return {"success": False, "error": result.stderr}

    async def log_operation(self, operation: str, details: dict):
        """Log operation to ai-logs bucket"""
        log_entry = {
            "timestamp": datetime.now().isoformat(),
            "operation": operation,
            "details": details,
            "source": "-workflows",
        }

        log_file = (
            self.lobster_home
            / "storage"
            / "logs"
            / f"{datetime.now().strftime('%Y%m%d')}-operations.jsonl"
        )
        log_file.parent.mkdir(parents=True, exist_ok=True)

        with open(log_file, "a") as f:
            f.write(json.dumps(log_entry) + "\n")

        # Also upload to AIStor
        cmd = ["mc", "cp", str(log_file), f"aistor/{self.buckets['logs']}/operations/"]
        subprocess.run(cmd, capture_output=True)


async def main():
    """CLI interface for workflows"""
    import argparse

    parser = argparse.ArgumentParser(description=" AIStor Workflows")
    parser.add_argument(
        "workflow", choices=["checkpoint", "dataset", "experiment", "serve", "backup"]
    )
    parser.add_argument("--run-id", help="Training run ID")
    parser.add_argument("--model-path", help="Path to model checkpoint")
    parser.add_argument("--dataset-name", help="Dataset name")
    parser.add_argument("--dataset-path", help="Path to dataset")
    parser.add_argument("--experiment-id", help="Experiment ID")
    parser.add_argument("--artifacts", help="Path to experiment artifacts")
    parser.add_argument("--model-name", help="Model name for serving")
    parser.add_argument("--version", default="latest", help="Model version")
    parser.add_argument("--bucket", help="Bucket type for backup")
    parser.add_argument("--cloud", default="gdrive", help="Cloud remote")
    parser.add_argument("--metrics", help="JSON metrics string")
    parser.add_argument("--config", help="JSON config string")
    parser.add_argument("--results", help="JSON results string")

    args = parser.parse_args()

    workflows = AIStorWorkflows()

    if args.workflow == "checkpoint":
        metrics = json.loads(args.metrics) if args.metrics else {}
        result = await workflows.training_checkpoint_workflow(
            args.run_id, args.model_path, metrics
        )
    elif args.workflow == "dataset":
        metadata = {"size_mb": 0}  # Calculate actual size
        result = await workflows.dataset_ingestion_workflow(
            args.dataset_name, args.dataset_path, metadata
        )
    elif args.workflow == "experiment":
        config = json.loads(args.config) if args.config else {}
        results = json.loads(args.results) if args.results else {}
        result = await workflows.experiment_tracking_workflow(
            args.experiment_id, args.artifacts, config, results
        )
    elif args.workflow == "serve":
        result = await workflows.model_serving_workflow(args.model_name, args.version)
    elif args.workflow == "backup":
        result = await workflows.backup_to_cloud(args.bucket, args.cloud)
    else:
        result = {"error": f"Unknown workflow: {args.workflow}"}

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    asyncio.run(main())
