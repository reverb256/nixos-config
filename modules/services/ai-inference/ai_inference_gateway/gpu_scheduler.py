"""
GPU Scheduler Integration for AI Inference Gateway

Signals GPU workload scheduler when AI workloads start/stop.
Enables explicit coordination instead of implicit process detection.
"""

import logging
import os
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

# GPU scheduler communication directory
SCHEDULER_STATE_DIR = Path("/run/gpu-scheduler")
SCHEDULER_STATE_FILE = SCHEDULER_STATE_DIR / "ai-state"

# State values
STATE_IDLE = ""
STATE_AI_STARTING = "AI_START"
STATE_AI_STOPPING = "AI_STOP"


def init_scheduler_comms() -> None:
    """Initialize GPU scheduler communication directory."""
    try:
        SCHEDULER_STATE_DIR.mkdir(parents=True, exist_ok=True)
        # Ensure permissions for scheduler to read/write
        os.chmod(SCHEDULER_STATE_DIR, 0o755)

        # Initialize to idle state
        if not SCHEDULER_STATE_FILE.exists():
            write_state(STATE_IDLE)

        logger.info(f"GPU scheduler comms initialized: {SCHEDULER_STATE_DIR}")
    except Exception as e:
        logger.error(f"Failed to initialize GPU scheduler comms: {e}")


def write_state(state: str) -> bool:
    """Write state to GPU scheduler."""
    try:
        SCHEDULER_STATE_FILE.write_text(state)
        logger.info(f"GPU scheduler signaled: {state}")
        return True
    except Exception as e:
        logger.error(f"Failed to signal GPU scheduler: {e}")
        return False


def notify_ai_starting() -> bool:
    """Signal GPU scheduler that AI workload is starting."""
    logger.info("Signaling GPU scheduler: AI workload starting")
    return write_state(STATE_AI_STARTING)


def notify_ai_stopping() -> bool:
    """Signal GPU scheduler that AI workload is stopping."""
    logger.info("Signaling GPU scheduler: AI workload stopping")
    return write_state(STATE_AI_STOPPING)


def notify_ai_idle() -> bool:
    """Signal GPU scheduler that AI workload is idle (no model loaded)."""
    logger.debug("Signaling GPU scheduler: AI workload idle")
    return write_state(STATE_IDLE)


def get_current_state() -> str:
    """Get current GPU scheduler state."""
    try:
        if SCHEDULER_STATE_FILE.exists():
            return SCHEDULER_STATE_FILE.read_text().strip()
        return STATE_IDLE
    except Exception:
        return STATE_IDLE
