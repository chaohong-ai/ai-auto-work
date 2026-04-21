# 测试模板参考：Tools/templates/test_template.py
# 新增测试文件时，可复制模板并根据注释提示自定义。
"""Shared fixtures for asset-pipeline tests."""

import io
import tempfile
from pathlib import Path
from unittest.mock import MagicMock

import pytest


@pytest.fixture
def sample_images(tmp_path: Path) -> list[Path]:
    """Create a set of minimal test images in a temp directory.

    Returns a list of Path objects pointing to 3 small PNG files.
    """
    from PIL import Image

    paths = []
    for i in range(3):
        img = Image.new("RGB", (64, 64), color=(i * 80, 100, 200))
        p = tmp_path / f"test_asset_{i}.png"
        img.save(p, format="PNG")
        paths.append(p)
    return paths


@pytest.fixture
def mock_cos() -> MagicMock:
    """Return a mock Tencent COS client.

    Provides stubbed put_object and head_object methods.
    """
    client = MagicMock()
    client.put_object.return_value = {"ETag": '"fake-etag-12345"'}
    client.head_object.return_value = {
        "Content-Length": "1024",
        "Content-Type": "image/png",
    }
    return client


@pytest.fixture
def mock_mongodb() -> MagicMock:
    """Return a mock MongoDB collection.

    Provides stubbed insert_one, find_one, and update_one methods.
    """
    collection = MagicMock()
    collection.insert_one.return_value = MagicMock(
        inserted_id="fake-object-id"
    )
    collection.find_one.return_value = {
        "_id": "fake-object-id",
        "name": "test_asset",
        "type": "sprite",
    }
    collection.update_one.return_value = MagicMock(modified_count=1)
    return collection


@pytest.fixture
def mock_milvus() -> MagicMock:
    """Return a mock Milvus client.

    Provides stubbed insert and search methods.
    """
    client = MagicMock()
    client.insert.return_value = MagicMock(
        primary_keys=["fake-pk-001"]
    )
    client.search.return_value = [[
        MagicMock(id="fake-pk-001", distance=0.95, entity={"name": "test_asset"}),
    ]]
    return client
