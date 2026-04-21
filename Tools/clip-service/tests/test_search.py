"""Tests for the /search endpoint (text/image search, empty query, filter, pagination)."""

import base64

import pytest


# ---------------------------------------------------------------------------
# Text search
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_search_text_returns_results(search_client, mock_milvus):
    """POST /search with text query should return search results from Milvus."""
    resp = await search_client.post("/search", json={"text": "fire ball sprite"})
    assert resp.status_code == 200

    data = resp.json()
    assert data["total"] >= 1
    assert data["results"][0]["id"] == "asset-001"
    assert data["results"][0]["score"] == 0.95
    assert "name" in data["results"][0]["metadata"]
    mock_milvus.search.assert_called_once()


# ---------------------------------------------------------------------------
# Image search
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_search_image_returns_results(search_client, sample_image, mock_milvus):
    """POST /search with image_base64 should return search results."""
    b64 = base64.b64encode(sample_image).decode()
    resp = await search_client.post("/search", json={"image_base64": b64})
    assert resp.status_code == 200

    data = resp.json()
    assert data["total"] >= 1
    assert data["results"][0]["id"] == "asset-001"
    mock_milvus.search.assert_called_once()


# ---------------------------------------------------------------------------
# Empty query
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_search_empty_query_returns_422(search_client):
    """POST /search with neither text nor image should return 422."""
    resp = await search_client.post("/search", json={})
    assert resp.status_code == 422
    assert "either" in resp.json()["detail"].lower()


# ---------------------------------------------------------------------------
# Filter expression
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_search_with_filter(search_client, mock_milvus):
    """POST /search with filter_expr should pass filter to Milvus."""
    resp = await search_client.post(
        "/search",
        json={"text": "tree", "filter_expr": 'type == "2d_sprite"'},
    )
    assert resp.status_code == 200

    call_kwargs = mock_milvus.search.call_args
    assert call_kwargs.kwargs["filter"] == 'type == "2d_sprite"'


# ---------------------------------------------------------------------------
# Pagination (limit / offset)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_search_pagination_params(search_client, mock_milvus):
    """POST /search with limit and offset should forward them to Milvus."""
    resp = await search_client.post(
        "/search",
        json={"text": "sound effect", "limit": 5, "offset": 10},
    )
    assert resp.status_code == 200

    call_kwargs = mock_milvus.search.call_args
    assert call_kwargs.kwargs["limit"] == 5
    assert call_kwargs.kwargs["offset"] == 10
