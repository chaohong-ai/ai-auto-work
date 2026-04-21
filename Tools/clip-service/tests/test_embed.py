"""Tests for the embedding endpoints (/embed/text, /embed/image, /embed/image/base64)."""

import base64
import io
import math

import pytest


# ---------------------------------------------------------------------------
# POST /embed/text
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_embed_text_returns_768d_vector(test_client):
    """POST /embed/text with valid text should return a 768-d embedding."""
    resp = await test_client.post("/embed/text", json={"text": "a red car"})
    assert resp.status_code == 200

    data = resp.json()
    assert data["dim"] == 768
    assert len(data["embedding"]) == 768
    assert isinstance(data["model"], str)


@pytest.mark.asyncio
async def test_embed_text_embedding_is_normalized(test_client):
    """The returned text embedding should be L2-normalized (magnitude ~1.0)."""
    resp = await test_client.post("/embed/text", json={"text": "hello world"})
    data = resp.json()

    magnitude = math.sqrt(sum(x * x for x in data["embedding"]))
    assert abs(magnitude - 1.0) < 1e-4


@pytest.mark.asyncio
async def test_embed_text_different_inputs_return_same_shape(test_client):
    """Different text inputs should all produce 768-d vectors."""
    for text in ["cat", "a very long sentence about game design"]:
        resp = await test_client.post("/embed/text", json={"text": text})
        assert resp.status_code == 200
        assert resp.json()["dim"] == 768


@pytest.mark.asyncio
async def test_embed_text_success_returns_model_field(test_client):
    """POST /embed/text success response includes the model name."""
    resp = await test_client.post("/embed/text", json={"text": "sprite"})
    assert resp.status_code == 200
    data = resp.json()
    assert "model" in data
    assert len(data["model"]) > 0


# ---------------------------------------------------------------------------
# POST /embed/text — invalid format scenarios
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_embed_text_invalid_json_body(test_client):
    """POST /embed/text with non-JSON body should return 422."""
    resp = await test_client.post(
        "/embed/text",
        content=b"not json",
        headers={"Content-Type": "application/json"},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_embed_text_wrong_field_name(test_client):
    """POST /embed/text with wrong field name should return 422."""
    resp = await test_client.post("/embed/text", json={"query": "hello"})
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# POST /embed/image
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_embed_image_returns_768d_vector(test_client, sample_image):
    """POST /embed/image with a valid PNG should return a 768-d embedding."""
    resp = await test_client.post(
        "/embed/image",
        files={"file": ("test.png", io.BytesIO(sample_image), "image/png")},
    )
    assert resp.status_code == 200

    data = resp.json()
    assert data["dim"] == 768
    assert len(data["embedding"]) == 768


@pytest.mark.asyncio
async def test_embed_image_embedding_is_normalized(test_client, sample_image):
    """The returned image embedding should be L2-normalized."""
    resp = await test_client.post(
        "/embed/image",
        files={"file": ("test.png", io.BytesIO(sample_image), "image/png")},
    )
    data = resp.json()

    magnitude = math.sqrt(sum(x * x for x in data["embedding"]))
    assert abs(magnitude - 1.0) < 1e-4


@pytest.mark.asyncio
async def test_embed_image_invalid_format_not_image(test_client):
    """POST /embed/image with a text file claiming image type should return 422."""
    resp = await test_client.post(
        "/embed/image",
        files={"file": ("readme.txt", io.BytesIO(b"just text"), "text/plain")},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_embed_image_too_large(test_client):
    """POST /embed/image with >20 MB file should return 413."""
    oversized = b"\x00" * (20 * 1024 * 1024 + 1)
    resp = await test_client.post(
        "/embed/image",
        files={"file": ("big.png", io.BytesIO(oversized), "image/png")},
    )
    assert resp.status_code == 413
    assert "too large" in resp.json()["detail"].lower()


# ---------------------------------------------------------------------------
# POST /embed/image/base64
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_embed_image_base64_returns_768d_vector(test_client, sample_image):
    """POST /embed/image/base64 with valid base64 PNG should return 768-d."""
    b64 = base64.b64encode(sample_image).decode()
    resp = await test_client.post(
        "/embed/image/base64", json={"image_base64": b64}
    )
    assert resp.status_code == 200

    data = resp.json()
    assert data["dim"] == 768
    assert len(data["embedding"]) == 768


@pytest.mark.asyncio
async def test_embed_image_base64_embedding_is_normalized(test_client, sample_image):
    """The returned base64-image embedding should be L2-normalized."""
    b64 = base64.b64encode(sample_image).decode()
    resp = await test_client.post(
        "/embed/image/base64", json={"image_base64": b64}
    )
    data = resp.json()

    magnitude = math.sqrt(sum(x * x for x in data["embedding"]))
    assert abs(magnitude - 1.0) < 1e-4


@pytest.mark.asyncio
async def test_embed_image_base64_too_large(test_client):
    """POST /embed/image/base64 with >20 MB decoded data should return 413."""
    oversized = b"\x00" * (20 * 1024 * 1024 + 1)
    b64 = base64.b64encode(oversized).decode()
    resp = await test_client.post(
        "/embed/image/base64", json={"image_base64": b64}
    )
    assert resp.status_code == 413


# ---------------------------------------------------------------------------
# Batch-style: multiple sequential requests
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_embed_text_batch_multiple_requests(test_client):
    """Multiple sequential /embed/text requests should all succeed independently."""
    texts = ["cat", "dog", "fire sprite", "explosion sound effect"]
    for text in texts:
        resp = await test_client.post("/embed/text", json={"text": text})
        assert resp.status_code == 200
        data = resp.json()
        assert data["dim"] == 768
        assert len(data["embedding"]) == 768


@pytest.mark.asyncio
async def test_embed_image_batch_multiple_requests(test_client, sample_image):
    """Multiple sequential /embed/image requests should all return 768-d vectors."""
    for _ in range(3):
        resp = await test_client.post(
            "/embed/image",
            files={"file": ("img.png", io.BytesIO(sample_image), "image/png")},
        )
        assert resp.status_code == 200
        assert resp.json()["dim"] == 768


# ---------------------------------------------------------------------------
# 503 when model is not loaded
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_embed_text_503_when_model_not_loaded(test_client):
    """POST /embed/text should return 503 when model state is None."""
    from main import _state

    original = _state.model
    _state.model = None
    try:
        resp = await test_client.post("/embed/text", json={"text": "hello"})
        assert resp.status_code == 503
        assert "not loaded" in resp.json()["detail"].lower()
    finally:
        _state.model = original


@pytest.mark.asyncio
async def test_embed_image_503_when_model_not_loaded(test_client, sample_image):
    """POST /embed/image should return 503 when model state is None."""
    from main import _state

    original = _state.model
    _state.model = None
    try:
        resp = await test_client.post(
            "/embed/image",
            files={"file": ("test.png", io.BytesIO(sample_image), "image/png")},
        )
        assert resp.status_code == 503
    finally:
        _state.model = original
