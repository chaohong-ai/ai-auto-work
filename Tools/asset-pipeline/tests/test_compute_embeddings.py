"""Tests for compute_embeddings.py — batch CLIP embedding computation."""

from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

from compute_embeddings import (
    resolve_asset_path,
    compute_embedding_for_row,
    load_manifest,
    embed_text,
    embed_image,
    ASSET_TYPE_EXT,
)


FAKE_VEC = [0.1] * 10


# ---------------------------------------------------------------------------
# resolve_asset_path
# ---------------------------------------------------------------------------


class TestResolveAssetPath:
    """Unit tests for asset path resolution."""

    def test_2d_sprite(self, tmp_path: Path):
        row = {"name": "Fire Ball", "type": "2d_sprite"}
        result = resolve_asset_path(row, tmp_path)
        assert result == tmp_path / "2d" / "fire_ball.png"

    def test_3d_model(self, tmp_path: Path):
        row = {"name": "Big Tree", "type": "3d_model"}
        result = resolve_asset_path(row, tmp_path)
        assert result == tmp_path / "3d" / "big_tree.glb"

    def test_audio_sfx(self, tmp_path: Path):
        row = {"name": "Boom Sound", "type": "audio_sfx"}
        result = resolve_asset_path(row, tmp_path)
        assert result == tmp_path / "audio" / "boom_sound.mp3"

    def test_unknown_type_returns_none(self, tmp_path: Path):
        row = {"name": "Mystery", "type": "unknown_thing"}
        assert resolve_asset_path(row, tmp_path) is None

    def test_empty_type_returns_none(self, tmp_path: Path):
        row = {"name": "Nothing", "type": ""}
        assert resolve_asset_path(row, tmp_path) is None


# ---------------------------------------------------------------------------
# compute_embedding_for_row — single image embedding
# ---------------------------------------------------------------------------


class TestComputeEmbeddingSingleImage:
    """Tests for 2D sprite image embedding path."""

    @patch("compute_embeddings.embed_image", return_value=FAKE_VEC)
    def test_2d_sprite_with_image(self, mock_embed, sample_images):
        asset_root = sample_images[0].parent
        img_dir = asset_root / "2d"
        img_dir.mkdir(exist_ok=True)
        target = img_dir / "test_asset_0.png"
        sample_images[0].rename(target)

        row = {"name": "Test Asset 0", "type": "2d_sprite", "prompt": "a sprite"}
        result = compute_embedding_for_row(row, asset_root, "http://fake", use_text_fallback=False)

        assert result["embed_source"] == "image"
        assert result["embedding"] == FAKE_VEC
        assert result["name"] == "Test Asset 0"
        assert result["type"] == "2d_sprite"
        mock_embed.assert_called_once()

    @patch("compute_embeddings.embed_text", return_value=FAKE_VEC)
    def test_2d_sprite_missing_image_with_fallback(self, mock_embed, tmp_path: Path):
        row = {"name": "Ghost", "type": "2d_sprite", "prompt": "a ghost sprite"}
        result = compute_embedding_for_row(row, tmp_path, "http://fake", use_text_fallback=True)

        assert result["embed_source"] == "text_fallback"
        assert result["embedding"] == FAKE_VEC
        mock_embed.assert_called_once_with("a ghost sprite", "http://fake")

    def test_2d_sprite_missing_image_no_fallback(self, tmp_path: Path):
        row = {"name": "Ghost", "type": "2d_sprite", "prompt": "a ghost sprite"}
        result = compute_embedding_for_row(row, tmp_path, "http://fake", use_text_fallback=False)

        assert result["status"] == "skipped"
        assert "not found" in result["reason"]


# ---------------------------------------------------------------------------
# compute_embedding_for_row — batch / multi-type
# ---------------------------------------------------------------------------


class TestComputeEmbeddingBatch:
    """Tests for audio, 3D, and mixed-type embedding."""

    @patch("compute_embeddings.embed_text", return_value=FAKE_VEC)
    def test_audio_uses_text_embedding(self, mock_embed, tmp_path: Path):
        row = {"name": "Boom", "type": "audio_sfx", "prompt": "explosion sound"}
        result = compute_embedding_for_row(row, tmp_path, "http://fake", use_text_fallback=False)

        assert result["embed_source"] == "text"
        assert result["embedding"] == FAKE_VEC
        mock_embed.assert_called_once_with("explosion sound", "http://fake")

    @patch("compute_embeddings.embed_text", return_value=FAKE_VEC)
    def test_3d_model_uses_text_embedding(self, mock_embed, tmp_path: Path):
        row = {"name": "Tree", "type": "3d_model", "prompt": "a low-poly tree"}
        result = compute_embedding_for_row(row, tmp_path, "http://fake", use_text_fallback=False)

        assert result["embed_source"] == "text"
        assert result["embedding"] == FAKE_VEC
        mock_embed.assert_called_once_with("a low-poly tree", "http://fake")

    @patch("compute_embeddings.embed_text", return_value=FAKE_VEC)
    @patch("compute_embeddings.embed_image", return_value=FAKE_VEC)
    def test_mixed_types_batch(self, mock_img, mock_txt, sample_images):
        """Simulate a batch: 2D with image, audio, 3D — verify correct embed_source."""
        asset_root = sample_images[0].parent
        img_dir = asset_root / "2d"
        img_dir.mkdir(exist_ok=True)
        target = img_dir / "sprite_one.png"
        sample_images[0].rename(target)

        rows = [
            {"name": "Sprite One", "type": "2d_sprite", "prompt": "sprite"},
            {"name": "SFX One", "type": "audio_sfx", "prompt": "sound"},
            {"name": "Model One", "type": "3d_model", "prompt": "model"},
        ]
        results = [
            compute_embedding_for_row(r, asset_root, "http://fake", use_text_fallback=False)
            for r in rows
        ]

        assert results[0]["embed_source"] == "image"
        assert results[1]["embed_source"] == "text"
        assert results[2]["embed_source"] == "text"


# ---------------------------------------------------------------------------
# compute_embedding_for_row — abnormal image skip
# ---------------------------------------------------------------------------


class TestAbnormalImageSkip:
    """Tests for skipping when image is missing or type is unknown."""

    def test_unknown_type_skipped(self, tmp_path: Path):
        row = {"name": "Mystery", "type": "unknown", "prompt": "???"}
        result = compute_embedding_for_row(row, tmp_path, "http://fake", use_text_fallback=False)
        # Unknown type has no asset_path, not audio/3d, so hits skipped path
        assert result.get("status") == "skipped"

    @patch("compute_embeddings.embed_image", side_effect=RuntimeError("CLIP service down"))
    def test_clip_service_error_propagates(self, mock_embed, sample_images):
        """When the CLIP service is down, the error propagates (not silently swallowed)."""
        asset_root = sample_images[0].parent
        img_dir = asset_root / "2d"
        img_dir.mkdir(exist_ok=True)
        target = img_dir / "broken_sprite.png"
        sample_images[0].rename(target)

        row = {"name": "Broken Sprite", "type": "2d_sprite", "prompt": "broken"}
        with pytest.raises(RuntimeError, match="CLIP service down"):
            compute_embedding_for_row(row, asset_root, "http://fake", use_text_fallback=False)


# ---------------------------------------------------------------------------
# embed_text / embed_image — retry behavior (external service mock)
# ---------------------------------------------------------------------------


class TestEmbedRetry:
    """Tests for CLIP embed helpers retry and error handling."""

    @patch("compute_embeddings.requests.post")
    def test_embed_text_success(self, mock_post):
        mock_resp = MagicMock()
        mock_resp.json.return_value = {"embedding": [0.5, 0.6]}
        mock_resp.raise_for_status = MagicMock()
        mock_post.return_value = mock_resp

        result = embed_text("test prompt", "http://clip:8000")
        assert result == [0.5, 0.6]
        mock_post.assert_called_once()

    @patch("compute_embeddings.requests.post")
    def test_embed_text_all_retries_fail(self, mock_post):
        import requests as req

        mock_post.side_effect = req.RequestException("timeout")
        with pytest.raises(RuntimeError, match="Failed to embed text"):
            embed_text("test", "http://clip:8000", max_retries=3)
        assert mock_post.call_count == 3

    @patch("compute_embeddings.requests.post")
    def test_embed_image_success(self, mock_post, sample_images):
        mock_resp = MagicMock()
        mock_resp.json.return_value = {"embedding": [0.7, 0.8]}
        mock_resp.raise_for_status = MagicMock()
        mock_post.return_value = mock_resp

        result = embed_image(sample_images[0], "http://clip:8000")
        assert result == [0.7, 0.8]

    @patch("compute_embeddings.requests.post")
    def test_embed_image_all_retries_fail(self, mock_post, sample_images):
        import requests as req

        mock_post.side_effect = req.RequestException("conn refused")
        with pytest.raises(RuntimeError, match="Failed to embed image"):
            embed_image(sample_images[0], "http://clip:8000", max_retries=3)
        assert mock_post.call_count == 3

    @patch("compute_embeddings.requests.post")
    def test_embed_text_recovers_on_retry(self, mock_post):
        """First attempt fails, second succeeds."""
        import requests as req

        ok_resp = MagicMock()
        ok_resp.json.return_value = {"embedding": [0.9]}
        ok_resp.raise_for_status = MagicMock()

        mock_post.side_effect = [req.RequestException("blip"), ok_resp]

        result = embed_text("retry me", "http://clip:8000", max_retries=2)
        assert result == [0.9]
        assert mock_post.call_count == 2


# ---------------------------------------------------------------------------
# load_manifest
# ---------------------------------------------------------------------------


class TestLoadManifest:
    """Tests for CSV manifest loading."""

    def test_load_valid(self, tmp_path: Path):
        csv_file = tmp_path / "m.csv"
        csv_file.write_text(
            "name,type,prompt\nA,2d_sprite,a\nB,audio_sfx,b\n", encoding="utf-8"
        )
        rows = load_manifest(str(csv_file))
        assert len(rows) == 2
        assert rows[1]["type"] == "audio_sfx"

    def test_empty_manifest(self, tmp_path: Path):
        csv_file = tmp_path / "empty.csv"
        csv_file.write_text("name,type,prompt\n", encoding="utf-8")
        assert load_manifest(str(csv_file)) == []
