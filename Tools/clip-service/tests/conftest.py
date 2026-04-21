# 测试模板参考：Tools/templates/test_template.py
# 新增测试文件时，可复制模板并根据注释提示自定义。
"""Shared fixtures for clip-service tests."""

import io
from unittest.mock import MagicMock

import pytest


@pytest.fixture
def mock_clip_model():
    """Return a mock CLIP model that produces fake embeddings.

    The mock model exposes encode_text and encode_image methods,
    each returning a tensor-like object with a deterministic 768-d vector.
    """
    import torch

    model = MagicMock()
    fake_embedding = torch.randn(1, 768)

    model.encode_text.return_value = fake_embedding
    model.encode_image.return_value = fake_embedding
    model.eval.return_value = None
    return model


@pytest.fixture
def sample_image() -> bytes:
    """Return a minimal valid PNG image as raw bytes."""
    from PIL import Image

    buf = io.BytesIO()
    img = Image.new("RGB", (32, 32), color=(128, 64, 196))
    img.save(buf, format="PNG")
    buf.seek(0)
    return buf.read()


@pytest.fixture
def sample_embedding() -> list[float]:
    """Return a pre-computed 768-d normalized embedding vector for testing."""
    import math

    # Uniform vector, then L2-normalize
    raw = [1.0] * 768
    magnitude = math.sqrt(sum(x * x for x in raw))
    return [x / magnitude for x in raw]


@pytest.fixture
def mock_milvus(sample_embedding):
    """Return a mock Milvus client for /search endpoint tests.

    The mock returns a single hit with a known ID and score.
    """
    client = MagicMock()
    hit = {
        "id": "asset-001",
        "distance": 0.95,
        "entity": {"name": "fire_ball", "type": "2d_sprite"},
    }
    client.search.return_value = [[hit]]
    return client


@pytest.fixture
def test_client(mock_clip_model, sample_image):
    """Return an httpx AsyncClient bound to the FastAPI app with mocked model.

    Usage in tests:
        async def test_health(test_client):
            resp = await test_client.get("/health")
            assert resp.status_code == 200
    """
    import torch
    from httpx import ASGITransport, AsyncClient

    from main import _state, app

    # Inject mock model into app state
    _state.model = mock_clip_model
    _state.tokenizer = MagicMock(
        return_value=torch.zeros(1, 77, dtype=torch.long)
    )

    # Create a mock preprocess that returns a valid tensor
    def _mock_preprocess(pil_img):
        return torch.randn(3, 224, 224)

    _state.preprocess = _mock_preprocess

    transport = ASGITransport(app=app)
    client = AsyncClient(transport=transport, base_url="http://test")

    yield client

    # Cleanup
    _state.model = None
    _state.preprocess = None
    _state.tokenizer = None
    _state.milvus = None


@pytest.fixture
def search_client(test_client, mock_milvus):
    """Return a test client with both CLIP model and Milvus mocked.

    Extends test_client by injecting a mock Milvus client into _state.
    """
    from main import _state

    _state.milvus = mock_milvus
    yield test_client
    _state.milvus = None
