"""Tests for quality_check.py — CLIP-based quality gate."""

import math
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

from quality_check import (
    cosine_similarity,
    resolve_image_path,
    check_row,
    load_manifest,
    embed_text,
    embed_image,
)


# ---------------------------------------------------------------------------
# cosine_similarity
# ---------------------------------------------------------------------------


class TestCosineSimilarity:
    """Unit tests for the cosine_similarity helper."""

    def test_identical_vectors(self):
        vec = [1.0, 2.0, 3.0]
        assert cosine_similarity(vec, vec) == pytest.approx(1.0)

    def test_orthogonal_vectors(self):
        a = [1.0, 0.0]
        b = [0.0, 1.0]
        assert cosine_similarity(a, b) == pytest.approx(0.0)

    def test_opposite_vectors(self):
        a = [1.0, 0.0]
        b = [-1.0, 0.0]
        assert cosine_similarity(a, b) == pytest.approx(-1.0)

    def test_zero_vector_returns_zero(self):
        a = [0.0, 0.0, 0.0]
        b = [1.0, 2.0, 3.0]
        assert cosine_similarity(a, b) == 0.0

    def test_known_value(self):
        a = [1.0, 2.0, 3.0]
        b = [4.0, 5.0, 6.0]
        dot = 1 * 4 + 2 * 5 + 3 * 6  # 32
        norm_a = math.sqrt(14)
        norm_b = math.sqrt(77)
        expected = dot / (norm_a * norm_b)
        assert cosine_similarity(a, b) == pytest.approx(expected)


# ---------------------------------------------------------------------------
# resolve_image_path
# ---------------------------------------------------------------------------


class TestResolveImagePath:
    """Unit tests for resolve_image_path."""

    def test_2d_sprite_resolves(self, tmp_path: Path):
        row = {"name": "Fire Ball", "type": "2d_sprite"}
        result = resolve_image_path(row, tmp_path)
        assert result == tmp_path / "2d" / "fire_ball.png"

    def test_non_visual_returns_none(self):
        row = {"name": "Explosion", "type": "audio_sfx"}
        assert resolve_image_path(row, Path("output")) is None

    def test_3d_model_returns_none(self):
        row = {"name": "Tree", "type": "3d_model"}
        assert resolve_image_path(row, Path("output")) is None


# ---------------------------------------------------------------------------
# check_row — with mocked CLIP service
# ---------------------------------------------------------------------------


FAKE_IMG_VEC = [1.0, 0.0, 0.0]
FAKE_TXT_VEC = [0.8, 0.6, 0.0]


class TestCheckRow:
    """Tests for check_row with mocked embed_image / embed_text."""

    @patch("quality_check.embed_text", return_value=FAKE_TXT_VEC)
    @patch("quality_check.embed_image", return_value=FAKE_IMG_VEC)
    def test_visual_asset_passes(self, mock_img, mock_txt, sample_images):
        asset_root = sample_images[0].parent
        # Place image where resolve_image_path expects it
        img_dir = asset_root / "2d"
        img_dir.mkdir(exist_ok=True)
        target = img_dir / "test_asset_0.png"
        sample_images[0].rename(target)

        row = {"name": "Test Asset 0", "type": "2d_sprite", "prompt": "a sprite"}
        result = check_row(row, asset_root, "http://fake", threshold=0.1)

        assert result["passed"] is True
        assert result["check_type"] == "image_text"
        assert result["score"] == pytest.approx(
            cosine_similarity(FAKE_IMG_VEC, FAKE_TXT_VEC), abs=1e-3
        )
        mock_img.assert_called_once()
        mock_txt.assert_called_once()

    @patch("quality_check.embed_text", return_value=FAKE_TXT_VEC)
    @patch("quality_check.embed_image", return_value=FAKE_IMG_VEC)
    def test_visual_asset_fails_threshold(self, mock_img, mock_txt, sample_images):
        asset_root = sample_images[0].parent
        img_dir = asset_root / "2d"
        img_dir.mkdir(exist_ok=True)
        target = img_dir / "test_asset_0.png"
        sample_images[0].rename(target)

        row = {"name": "Test Asset 0", "type": "2d_sprite", "prompt": "a sprite"}
        # Very high threshold so it fails
        result = check_row(row, asset_root, "http://fake", threshold=0.99)

        assert result["passed"] is False
        assert result["check_type"] == "image_text"

    def test_missing_image_fails(self, tmp_path: Path):
        row = {"name": "Ghost", "type": "2d_sprite", "prompt": "a ghost"}
        result = check_row(row, tmp_path, "http://fake", threshold=0.25)

        assert result["passed"] is False
        assert result["score"] is None
        assert "not found" in result.get("reason", "").lower()

    def test_non_visual_asset_passes(self, tmp_path: Path):
        row = {"name": "Boom", "type": "audio_sfx", "prompt": "explosion sound"}
        result = check_row(row, tmp_path, "http://fake", threshold=0.25)

        assert result["passed"] is True
        assert result["check_type"] == "n/a"

    def test_3d_model_marked_na(self, tmp_path: Path):
        row = {"name": "Tree", "type": "3d_model", "prompt": "a tree"}
        result = check_row(row, tmp_path, "http://fake", threshold=0.25)

        assert result["passed"] is True
        assert result["check_type"] == "n/a"


# ---------------------------------------------------------------------------
# load_manifest
# ---------------------------------------------------------------------------


class TestLoadManifest:
    """Tests for CSV manifest loading."""

    def test_load_valid_manifest(self, tmp_path: Path):
        csv_file = tmp_path / "manifest.csv"
        csv_file.write_text(
            "name,type,prompt\nFireball,2d_sprite,a fireball\nBoom,audio_sfx,boom\n",
            encoding="utf-8",
        )
        rows = load_manifest(str(csv_file))
        assert len(rows) == 2
        assert rows[0]["name"] == "Fireball"

    def test_empty_manifest(self, tmp_path: Path):
        csv_file = tmp_path / "manifest.csv"
        csv_file.write_text("name,type,prompt\n", encoding="utf-8")
        rows = load_manifest(str(csv_file))
        assert rows == []


# ---------------------------------------------------------------------------
# embed_text / embed_image — retry and error behavior
# ---------------------------------------------------------------------------


class TestEmbedRetry:
    """Tests for CLIP embed helpers retry logic."""

    @patch("quality_check.requests.post")
    def test_embed_text_success(self, mock_post):
        mock_resp = MagicMock()
        mock_resp.json.return_value = {"embedding": [0.1, 0.2]}
        mock_resp.raise_for_status = MagicMock()
        mock_post.return_value = mock_resp

        result = embed_text("hello", "http://clip:8000")
        assert result == [0.1, 0.2]

    @patch("quality_check.requests.post")
    def test_embed_text_retries_on_failure(self, mock_post):
        import requests as req

        mock_post.side_effect = [
            req.RequestException("timeout"),
            req.RequestException("timeout"),
            req.RequestException("timeout"),
        ]
        with pytest.raises(RuntimeError, match="Failed to embed text"):
            embed_text("hello", "http://clip:8000", max_retries=3)
        assert mock_post.call_count == 3

    @patch("quality_check.requests.post")
    def test_embed_image_success(self, mock_post, sample_images):
        mock_resp = MagicMock()
        mock_resp.json.return_value = {"embedding": [0.3, 0.4]}
        mock_resp.raise_for_status = MagicMock()
        mock_post.return_value = mock_resp

        result = embed_image(sample_images[0], "http://clip:8000")
        assert result == [0.3, 0.4]

    @patch("quality_check.requests.post")
    def test_embed_image_retries_on_failure(self, mock_post, sample_images):
        import requests as req

        mock_post.side_effect = [
            req.RequestException("conn error"),
            req.RequestException("conn error"),
            req.RequestException("conn error"),
        ]
        with pytest.raises(RuntimeError, match="Failed to embed image"):
            embed_image(sample_images[0], "http://clip:8000", max_retries=3)
        assert mock_post.call_count == 3
