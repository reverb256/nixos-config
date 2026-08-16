"""Astral Key authentication for the AI Inference Gateway.

Provides FastAPI dependencies that verify credentials against the Astral Key
service (https://github.com/reverb256/astral-key). Two credential types are
accepted via the ``Authorization: Bearer <token>`` header:

* API keys (``ak_*``)     — verified against ``POST /api/v1/auth/keys/verify``.
* JWT session tokens       — verified against ``POST /api/v1/auth/verify``.

Configuration (via ``GatewayConfig`` / environment variables):

* ``ASTRAL_KEY_URL``          — Astral Key base URL. If unset, admin endpoints
  fail closed with 503 (they never fall back to open access).
* ``ASTRAL_KEY_ADMIN_SCOPES`` — optional comma-separated scopes that a
  credential must carry for admin access. API keys carry scopes; JWTs do not,
  so a JWT alone cannot satisfy a scoped admin check.
"""

from __future__ import annotations

import logging
import os
from typing import Optional

import httpx
from fastapi import HTTPException, Request, status

logger = logging.getLogger(__name__)


def _admin_scopes(raw: str) -> list[str]:
    """Split a comma-separated scope string into a clean list."""
    return [s.strip() for s in (raw or "").split(",") if s.strip()]


async def verify_credential(token: str, base_url: str) -> dict:
    """Verify a Bearer credential against Astral Key.

    Args:
        token: The raw bearer token (API key or JWT).
        base_url: Astral Key base URL (no trailing slash).

    Returns:
        The credential metadata dict on success.

    Raises:
        HTTPException: 401 on invalid credentials, 503 on backend failure.
    """
    token = (token or "").strip()
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if token.startswith("ak_"):
        endpoint = "keys/verify"
        payload = {"api_key": token}
    else:
        endpoint = "verify"
        payload = {"token": token}

    verify_url = f"{base_url.rstrip('/')}/api/v1/auth/{endpoint}"

    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.post(verify_url, json=payload)
    except httpx.HTTPError as exc:
        logger.error("Astral Key backend unreachable (%s): %s", verify_url, exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication backend unreachable",
        ) from exc

    if resp.status_code == 404:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication backend does not expose the verify endpoint",
        )

    try:
        data = resp.json()
    except ValueError:
        logger.error("Astral Key returned non-JSON response: %r", resp.text[:200])
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication backend returned an invalid response",
        )

    if not data.get("valid"):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=data.get("error") or "Invalid credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return data


async def require_admin(request: Request) -> dict:
    """FastAPI dependency: require a valid Astral Key credential.

    If ``ASTRAL_KEY_ADMIN_SCOPES`` is configured, the credential must carry at
    least one of those scopes (API keys carry scopes; JWTs do not).

    Fails closed (503) when ``ASTRAL_KEY_URL`` is not configured so that admin
    endpoints are never silently open.
    """
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    gateway = getattr(request.app.state, "gateway", None)
    config = getattr(gateway, "config", None)

    base_url: Optional[str] = (
        getattr(config, "astral_key_url", None) or os.environ.get("ASTRAL_KEY_URL")
    )
    if not base_url:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication backend not configured (set ASTRAL_KEY_URL)",
        )

    scopes_raw: str = (
        getattr(config, "astral_key_admin_scopes", None)
        or os.environ.get("ASTRAL_KEY_ADMIN_SCOPES", "")
    )

    token = header[len("Bearer ") :]
    principal = await verify_credential(token, base_url)

    required = _admin_scopes(scopes_raw)
    if required:
        granted = set(principal.get("scopes") or [])
        if not granted.intersection(required):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Credential lacks the required admin scope",
            )

    return principal
