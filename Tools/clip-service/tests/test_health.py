"""Tests for the /health endpoint."""

import pytest


@pytest.mark.asyncio
async def test_health_returns_200(test_client):
    """GET /health should return 200 with status, model, pretrained, device."""
    resp = await test_client.get("/health")
    assert resp.status_code == 200

    data = resp.json()
    assert data["status"] == "ok"
    assert "model" in data
    assert "pretrained" in data
    assert "device" in data


@pytest.mark.asyncio
async def test_health_contains_model_info(test_client):
    """GET /health should report non-empty model metadata."""
    resp = await test_client.get("/health")
    data = resp.json()

    assert isinstance(data["model"], str) and len(data["model"]) > 0
    assert isinstance(data["pretrained"], str) and len(data["pretrained"]) > 0
    assert data["device"] in ("cpu", "cuda")
