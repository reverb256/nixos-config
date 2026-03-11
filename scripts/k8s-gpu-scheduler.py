#!/usr/bin/env python3
"""
Kubernetes GPU Scheduling Controller

Integrates with the existing AI inference gateway signaling system
to manage mining pods based on GPU workload priorities.

 watches /run/gpu-scheduler/ai-state
- Manages mining pods (low-priority-mining)
- Coordinates with bare metal compute-workload-monitor
"""

import os
import time
import logging
import subprocess
from pathlib import Path
from typing import Optional

from kubernetes import client, config
from kubernetes.client.rest import ApiException

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('k8s-gpu-scheduler')

# GPU scheduler state file (same as compute-workload-monitor)
SCHEDULER_STATE_FILE = Path("/run/gpu-scheduler/ai-state")
SCHEDULER_STATE_DIR = SCHEDULER_STATE_FILE.parent

# Kubernetes configuration
MINING_NAMESPACE = "mining"
MINING_DEPLOYMENTS = ["gpu-miner-zephyr", "gpu-miner-forge"]

# State values (from gpu_scheduler.py)
STATE_IDLE = ""
STATE_AI_STARTING = "AI_START"
STATE_AI_STOPPING = "AI_STOP"

class K8sGPUScheduler:
    def __init__(self):
        """Initialize Kubernetes client and GPU scheduler state."""
        try:
            # Load in-cluster config
            config.load_incluster_config()
            logger.info("Loaded in-cluster Kubernetes config")
        except config.ConfigException:
            # Fall back to kubeconfig
            try:
                config.load_kube_config()
                logger.info("Loaded kubeconfig")
            except config.ConfigException as e:
                logger.error(f"Failed to load Kubernetes config: {e}")
                raise

        self.apps_v1 = client.AppsV1Api()
        self.core_v1 = client.CoreV1Api()

        self.last_state = STATE_IDLE
        self.mining_was_running = False

        # Ensure state directory exists
        SCHEDULER_STATE_DIR.mkdir(parents=True, exist_ok=True)

    def get_scheduler_state(self) -> str:
        """Read current GPU scheduler state from file."""
        try:
            if SCHEDULER_STATE_FILE.exists():
                return SCHEDULER_STATE_FILE.read_text().strip()
            return STATE_IDLE
        except Exception as e:
            logger.error(f"Failed to read scheduler state: {e}")
            return STATE_IDLE

    def scale_mining_deployments(self, replicas: int) -> bool:
        """Scale mining deployments to specified replica count."""
        success = True
        for deployment in MINING_DEPLOYMENTS:
            try:
                # Check if deployment exists
                self.apps_v1.read_namespaced_deployment(
                    name=deployment,
                    namespace=MINING_NAMESPACE
                )

                # Scale deployment
                body = {"spec": {"replicas": replicas}}
                self.apps_v1.patch_namespaced_deployment(
                    name=deployment,
                    namespace=MINING_NAMESPACE,
                    body=body
                )
                logger.info(f"Scaled {deployment} to {replicas} replicas")
            except ApiException as e:
                if e.status == 404:
                    logger.warning(f"Deployment {deployment} not found (skipping)")
                else:
                    logger.error(f"Failed to scale {deployment}: {e}")
                    success = False

        return success

    def stop_mining_pods(self) -> bool:
        """Stop all mining pods by scaling deployments to 0."""
        logger.info("Stopping mining pods (AI workload needs GPUs)")
        return self.scale_mining_deployments(0)

    def start_mining_pods(self) -> bool:
        """Start mining pods by scaling deployments to 1."""
        logger.info("Starting mining pods (GPUs available for mining)")
        return self.scale_mining_deployments(1)

    def get_mining_pod_count(self) -> int:
        """Get current number of running mining pods."""
        try:
            pods = self.core_v1.list_namespaced_pod(
                namespace=MINING_NAMESPACE,
                label_selector="app=gpu-miner"
            )

            # Count running pods
            running = sum(1 for pod in pods.items if pod.status.phase == "Running")
            logger.debug(f"Current mining pods: {running} running")
            return running
        except Exception as e:
            logger.error(f"Failed to get mining pod count: {e}")
            return 0

    def run_once(self) -> None:
        """Run one scheduling cycle."""
        current_state = self.get_scheduler_state()
        mining_pods = self.get_mining_pod_count()

        logger.debug(f"State: {current_state or 'IDLE'}, Mining pods: {mining_pods}")

        # State machine
        if current_state == STATE_AI_STARTING:
            # AI workload starting - stop mining immediately
            if mining_pods > 0:
                logger.info("AI workload starting - stopping mining pods")
                self.stop_mining_pods()
                self.mining_was_running = True

        elif current_state == STATE_AI_STOPPING or current_state == STATE_IDLE:
            # AI workload stopping or idle - start mining if it was running
            if self.mining_was_running and mining_pods == 0:
                logger.info("AI workload stopped - restarting mining pods")
                self.start_mining_pods()
                self.mining_was_running = False

        # Update last state
        if current_state != self.last_state:
            logger.info(f"State changed: {self.last_state or 'IDLE'} -> {current_state or 'IDLE'}")
            self.last_state = current_state

    def run(self, check_interval: int = 5) -> None:
        """Run the GPU scheduler controller loop."""
        logger.info("Kubernetes GPU Scheduler Controller starting")
        logger.info(f"Monitoring state file: {SCHEDULER_STATE_FILE}")
        logger.info(f"Managing deployments: {MINING_DEPLOYMENTS}")

        while True:
            try:
                self.run_once()
            except Exception as e:
                logger.error(f"Error in scheduling cycle: {e}", exc_info=True)

            time.sleep(check_interval)


def main():
    """Main entry point."""
    # Initialize state file if it doesn't exist
    if not SCHEDULER_STATE_FILE.exists():
        SCHEDULER_STATE_FILE.write_text(STATE_IDLE)
        logger.info(f"Initialized state file: {SCHEDULER_STATE_FILE}")

    # Create and run scheduler
    scheduler = K8sGPUScheduler()

    try:
        scheduler.run(check_interval=5)
    except KeyboardInterrupt:
        logger.info("Shutting down...")


if __name__ == "__main__":
    main()
