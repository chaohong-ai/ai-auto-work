"""Tests for input validation (invalid formats, oversized files, empty input)."""

import base64
import io

import pytest


# ---------------------------------------------------------------------------
# Empty / whitespace text input
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_embed_text_empty_string_returns_422(test_client):
    """POST /embed/text with empty text should return 422."""
    resp = await test_client.post("/embed/text", json={"text": ""})
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_embed_text_whitespace_only_returns_422(test_client):
    """POST /embed/text with whitespace-only text should return 422."""
    resp = await test_client.post("/embed/text", json={"text": "   "})
    assert resp.status_code == 422
    assert "empty" in resp.json()["detail"].lower()


# ---------------------------------------------------------------------------
# Invalid content type for /embed/image
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_embed_image_invalid_content_type_returns_422(test_client):
    """POST /embed/image with non-image content type should return 422."""
    resp = await test_client.post(
        "/embed/image",
        files={"file": ("data.txt", io.BytesIO(b"not an image"), "text/plain")},
    )
    assert resp.status_code == 422
    assert "content type" in resp.json()["detail"].lower()


@pytest.mark.asyncio
async def test_embed_image_application_json_content_type_returns_422(test_client):
    """POST /embed/image with application/json content type should be rejected."""
    resp = await test_client.post(
        "/embed/image",
        files={"file": ("data.json", io.BytesIO(b"{}"), "application/json")},
    )
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# Oversized file for /embed/image
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_embed_image_oversized_file_returns_413(test_client):
    """POST /embed/image with >20 MB file should return 413."""
    # 20 MB + 1 byte
    oversized = b"\x00" * (20 * 1024 * 1024 + 1)
    resp = await test_client.post(
        "/embed/image",
        files={"file": ("big.png", io.BytesIO(oversized), "image/png")},
    )
    assert resp.status_code == 413
    assert "too large" in resp.json()["detail"].lower()


# ---------------------------------------------------------------------------
# Corrupt / non-decodable image data
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_embed_image_corrupt_data_returns_422(test_client):
    """POST /embed/image with corrupt image bytes should return 422."""
    resp = await test_client.post(
        "/embed/image",
        files={"file": ("bad.png", io.BytesIO(b"not-a-png"), "image/png")},
    )
    assert resp.status_code == 422
    assert "cannot decode" in resp.json()["detail"].lower()


# ---------------------------------------------------------------------------
# Invalid base64 for /embed/image/base64
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_embed_image_base64_invalid_encoding_returns_422(test_client):
    """POST /embed/image/base64 with invalid base64 should return 422."""
    resp = await test_client.post(
        "/embed/image/base64", json={"image_base64": "%%%not-base64%%%"}
    )
    assert resp.status_code == 422
    assert "invalid base64" in resp.json()["detail"].lower()


@pytest.mark.asyncio
async def test_embed_image_base64_corrupt_image_returns_422(test_client):
    """POST /embed/image/base64 with valid base64 but non-image data returns 422."""
    b64 = base64.b64encode(b"this is not an image").decode()
    resp = await test_client.post(
        "/embed/image/base64", json={"image_base64": b64}
    )
    assert resp.status_code == 422
    assert "cannot decode" in resp.json()["detail"].lower()


# ---------------------------------------------------------------------------
# Oversized base64 image
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_embed_image_base64_oversized_returns_413(test_client):
    """POST /embed/image/base64 with >20 MB decoded data should return 413."""
    oversized = b"\x00" * (20 * 1024 * 1024 + 1)
    b64 = base64.b64encode(oversized).decode()
    resp = await test_client.post(
        "/embed/image/base64", json={"image_base64": b64}
    )
    assert resp.status_code == 413
    assert "too large" in resp.json()["detail"].lower()


# ---------------------------------------------------------------------------
# Missing required fields
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_embed_text_missing_text_field_returns_422(test_client):
    """POST /embed/text with no 'text' field should return 422."""
    resp = await test_client.post("/embed/text", json={})
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_embed_image_base64_missing_field_returns_422(test_client):
    """POST /embed/image/base64 with no 'image_base64' field should return 422."""
    resp = await test_client.post("/embed/image/base64", json={})
    assert resp.status_code == 422
