"""Tests for the Astral Key authentication dependency."""

from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import pytest
from fastapi import HTTPException

from ai_inference_gateway.auth import (
    _admin_scopes,
    require_admin,
    verify_credential,
)


class _FakeHeaders:
    def __init__(self, values=None):
        self._values = values or {}

    def get(self, key, default=None):
        return self._values.get(key, default)


class _FakeRequest:
    """Minimal stand-in for a FastAPI Request carrying gateway config."""

    def __init__(self, headers=None, config=None):
        self.headers = _FakeHeaders(headers)
        self.app = SimpleNamespace(
            state=SimpleNamespace(gateway=SimpleNamespace(config=config))
        )


def _response(status_code=200, payload=None):
    resp = Mock()
    resp.status_code = status_code
    resp.json.return_value = payload or {}
    resp.text = ""
    return resp


def test_admin_scopes_parsing():
    assert _admin_scopes("") == []
    assert _admin_scopes("a, b ,c") == ["a", "b", "c"]
    assert _admin_scopes("  ai-gateway:admin ") == ["ai-gateway:admin"]


@pytest.mark.asyncio
async def test_verify_credential_api_key(mock_httpx_client):
    mock_httpx_client.post = AsyncMock(
        return_value=_response(
            payload={"valid": True, "name": "k", "scopes": ["ai-gateway:admin"]}
        )
    )

    result = await verify_credential("ak_prod_abc", "http://astral-key:8080")

    assert result["valid"] is True
    call = mock_httpx_client.post.call_args
    assert call.args[0].endswith("/api/v1/auth/keys/verify")
    assert call.kwargs["json"] == {"api_key": "ak_prod_abc"}


@pytest.mark.asyncio
async def test_verify_credential_jwt(mock_httpx_client):
    mock_httpx_client.post = AsyncMock(
        return_value=_response(payload={"valid": True, "sub": "u1", "exp": 1})
    )

    result = await verify_credential("eyJhbGciOi...", "http://astral-key:8080")

    assert result["valid"] is True
    call = mock_httpx_client.post.call_args
    assert call.args[0].endswith("/api/v1/auth/verify")
    assert call.kwargs["json"] == {"token": "eyJhbGciOi..."}


@pytest.mark.asyncio
async def test_verify_credential_invalid(mock_httpx_client):
    mock_httpx_client.post = AsyncMock(
        return_value=_response(payload={"valid": False, "error": "Invalid API key"})
    )

    with pytest.raises(HTTPException) as exc:
        await verify_credential("ak_prod_bad", "http://astral-key:8080")

    assert exc.value.status_code == 401


@pytest.mark.asyncio
async def test_require_admin_missing_header(monkeypatch):
    monkeypatch.delenv("ASTRAL_KEY_URL", raising=False)
    req = _FakeRequest(headers={})

    with pytest.raises(HTTPException) as exc:
        await require_admin(req)

    assert exc.value.status_code == 401


@pytest.mark.asyncio
async def test_require_admin_fails_closed_without_url(monkeypatch):
    monkeypatch.delenv("ASTRAL_KEY_URL", raising=False)
    monkeypatch.delenv("GATEWAY_AUTH_URL", raising=False)
    req = _FakeRequest(
        headers={"Authorization": "Bearer ak_prod_abc"},
        config=SimpleNamespace(astral_key_url=None),
    )

    with pytest.raises(HTTPException) as exc:
        await require_admin(req)

    assert exc.value.status_code == 503


@pytest.mark.asyncio
async def test_require_admin_enforces_scopes(mock_httpx_client, monkeypatch):
    monkeypatch.setenv("ASTRAL_KEY_ADMIN_SCOPES", "ai-gateway:admin")
    mock_httpx_client.post = AsyncMock(
        return_value=_response(
            payload={"valid": True, "name": "k", "scopes": ["other:scope"]}
        )
    )
    req = _FakeRequest(
        headers={"Authorization": "Bearer ak_prod_abc"},
        config=SimpleNamespace(
            astral_key_url="http://astral-key:8080",
            astral_key_admin_scopes="ai-gateway:admin",
        ),
    )

    with pytest.raises(HTTPException) as exc:
        await require_admin(req)

    assert exc.value.status_code == 403
