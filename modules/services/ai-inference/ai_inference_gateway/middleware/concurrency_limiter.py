"""
Concurrency Limiter Middleware.

Limits concurrent requests per model to prevent overwhelming backends.
Uses asyncio.Semaphore to track and limit active requests.
"""

import logging
import asyncio
from typing import Dict
from .base import Middleware

logger = logging.getLogger(__name__)


class ConcurrencyLimiter(Middleware):
    """
    Limits concurrent requests per model.

    Ensures that only a specified number of concurrent requests
    can be processed for each model at any given time.
    """

    def __init__(self, max_concurrency: int = 1):
        """
        Initialize concurrency limiter.

        Args:
            max_concurrency: Maximum concurrent requests per model (default: 1)
        """
        self.max_concurrency = max_concurrency
        # Map of model name to semaphore
        self.semaphores: Dict[str, asyncio.Semaphore] = {}
        # Lock to protect access to semaphores dict
        self.lock = asyncio.Lock()

    async def _get_semaphore(self, model: str) -> asyncio.Semaphore:
        """
        Get or create semaphore for a model.

        Args:
            model: Model name

        Returns:
            Semaphore for the model
        """
        async with self.lock:
            if model not in self.semaphores:
                self.semaphores[model] = asyncio.Semaphore(self.max_concurrency)
                logger.info(f"Created semaphore for model: {model} (max_concurrency={self.max_concurrency})")
            return self.semaphores[model]

    async def process_request(self, request, context: dict) -> dict:
        """
        Acquire concurrency permit before processing request.

        Args:
            request: FastAPI request object
            context: Request context

        Returns:
            Modified context

        Raises:
            HTTPException: If concurrency limit is reached
        """
        from fastapi import HTTPException

        # Get model from context (set by previous middleware)
        model = context.get("model", "default")

        # Get semaphore for this model
        semaphore = await self._get_semaphore(model)

        # Try to acquire permit without blocking
        if semaphore.locked():
            # All permits are in use
            logger.warning(f"Concurrency limit reached for model: {model}")
            raise HTTPException(
                status_code=503,
                detail=f"Model {model} is at maximum concurrency ({self.max_concurrency}). Please retry later."
            )

        # Acquire permit
        await semaphore.acquire()
        logger.info(f"Acquired concurrency permit for model: {model} (active: {self.max_concurrency - semaphore._value})")

        # Store permit in context for release later
        context["_concurrency_permit"] = (semaphore, model)
        return context

    async def process_response(self, response, context: dict) -> dict:
        """
        Release concurrency permit after request completes.

        Args:
            response: Response object
            context: Request context

        Returns:
            Modified context
        """
        # Release permit if it was acquired
        if "_concurrency_permit" in context:
            semaphore, model = context["_concurrency_permit"]
            semaphore.release()
            logger.info(f"Released concurrency permit for model: {model} (active: {self.max_concurrency - semaphore._value})")
            context.pop("_concurrency_permit", None)

        return context

    async def on_error(self, error: Exception, context: dict):
        """
        Release concurrency permit on error.

        Args:
            error: Exception that occurred
            context: Request context
        """
        # Release permit if it was acquired
        if "_concurrency_permit" in context:
            semaphore, model = context["_concurrency_permit"]
            semaphore.release()
            logger.warning(f"Released concurrency permit for model: {model} due to error (active: {self.max_concurrency - semaphore._value})")
            context.pop("_concurrency_permit", None)
