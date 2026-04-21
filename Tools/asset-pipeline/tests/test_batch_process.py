"""Tests for batch processing logic (generate_2d.process_row / run).

Uses pytest parametrize to cover single, batch, invalid input, and partial failure scenarios.
"""

import argparse
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

from generate_2d import process_row, run, load_manifest, generate_image


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_args(**overrides) -> argparse.Namespace:
    """Build a default argparse.Namespace for generate_2d, with optional overrides."""
    defaults = {
        "manifest": "asset_manifest.csv",
        "output_dir": "output/2d",
        "sdxl_url": "http://localhost:7860",
        "steps": 30,
        "cfg_scale": 7.5,
        "width": 512,
        "height": 512,
        "negative_prompt": "blurry, low quality",
        "dry_run": False,
    }
    defaults.update(overrides)
    return argparse.Namespace(**defaults)


# ---------------------------------------------------------------------------
# Single asset processing
# ---------------------------------------------------------------------------


class TestProcessRowSingle:
    """Test process_row with a single valid row."""

    @patch("generate_2d.generate_image", return_value=b"\x89PNG fake image bytes")
    def test_single_success(self, mock_gen, tmp_path: Path):
        """A single valid row produces a success result and writes the file."""
        row = {"name": "Fire Ball", "prompt": "a fire ball sprite"}
        args = _make_args()
        result = process_row(row, tmp_path, "http://fake:7860", args)

        assert result["status"] == "success"
        assert result["name"] == "Fire Ball"
        assert (tmp_path / "fire_ball.png").exists()
        mock_gen.assert_called_once()

    def test_single_dry_run(self, tmp_path: Path):
        """Dry-run mode skips the API call and returns dry-run status."""
        row = {"name": "Fire Ball", "prompt": "a fire ball sprite"}
        args = _make_args(dry_run=True)
        result = process_row(row, tmp_path, "http://fake:7860", args)

        assert result["status"] == "dry-run"
        assert not (tmp_path / "fire_ball.png").exists()


# ---------------------------------------------------------------------------
# Batch processing (parametrized)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "rows,expected_success,expected_error",
    [
        pytest.param(
            [
                {"name": "Sprite A", "prompt": "sprite a"},
                {"name": "Sprite B", "prompt": "sprite b"},
                {"name": "Sprite C", "prompt": "sprite c"},
            ],
            3,
            0,
            id="batch-all-success",
        ),
        pytest.param(
            [],
            0,
            0,
            id="batch-empty-manifest",
        ),
    ],
)
@patch("generate_2d.generate_image", return_value=b"\x89PNG fake")
def test_batch_processing(mock_gen, rows, expected_success, expected_error, tmp_path: Path):
    """Batch processing should handle multiple rows and report correct counts."""
    args = _make_args()
    results = []
    for row in rows:
        result = process_row(row, tmp_path, "http://fake:7860", args)
        results.append(result)

    success = sum(1 for r in results if r["status"] == "success")
    errors = sum(1 for r in results if r["status"] == "error")
    assert success == expected_success
    assert errors == expected_error


# ---------------------------------------------------------------------------
# Invalid input
# ---------------------------------------------------------------------------


class TestProcessRowInvalidInput:
    """Test process_row with invalid or missing data."""

    @patch("generate_2d.generate_image", side_effect=RuntimeError("SDXL API request failed: Connection refused"))
    def test_api_failure_returns_error(self, mock_gen, tmp_path: Path):
        """When the SDXL API fails, process_row returns an error dict (not an exception)."""
        row = {"name": "Bad Sprite", "prompt": "a broken sprite"}
        args = _make_args()
        result = process_row(row, tmp_path, "http://fake:7860", args)

        assert result["status"] == "error"
        assert "SDXL API request failed" in result["error"]
        assert not (tmp_path / "bad_sprite.png").exists()


# ---------------------------------------------------------------------------
# Partial failure in batch
# ---------------------------------------------------------------------------


class TestBatchPartialFailure:
    """Test batch processing where some items succeed and some fail."""

    def test_partial_failure_mixed_results(self, tmp_path: Path):
        """In a batch of 3, if the 2nd fails, other results are still collected."""
        rows = [
            {"name": "Good One", "prompt": "good sprite"},
            {"name": "Bad One", "prompt": "bad sprite"},
            {"name": "Good Two", "prompt": "another good sprite"},
        ]
        args = _make_args()

        call_count = 0

        def _side_effect(**kwargs):
            nonlocal call_count
            call_count += 1
            if call_count == 2:
                raise RuntimeError("SDXL timeout")
            return b"\x89PNG fake image data"

        with patch("generate_2d.generate_image", side_effect=_side_effect):
            results = [
                process_row(row, tmp_path, "http://fake:7860", args)
                for row in rows
            ]

        statuses = [r["status"] for r in results]
        assert statuses == ["success", "error", "success"]
        assert (tmp_path / "good_one.png").exists()
        assert not (tmp_path / "bad_one.png").exists()
        assert (tmp_path / "good_two.png").exists()


# ---------------------------------------------------------------------------
# load_manifest — filters by source == 'sdxl'
# ---------------------------------------------------------------------------


class TestLoadManifest:
    """Tests for generate_2d.load_manifest CSV filtering."""

    def test_filters_sdxl_rows(self, tmp_path: Path):
        csv_file = tmp_path / "manifest.csv"
        csv_file.write_text(
            "name,prompt,source\n"
            "A,sprite a,sdxl\n"
            "B,sound b,elevenlabs\n"
            "C,sprite c,SDXL\n",
            encoding="utf-8",
        )
        rows = load_manifest(str(csv_file))
        assert len(rows) == 2
        assert rows[0]["name"] == "A"
        assert rows[1]["name"] == "C"

    def test_empty_manifest(self, tmp_path: Path):
        csv_file = tmp_path / "empty.csv"
        csv_file.write_text("name,prompt,source\n", encoding="utf-8")
        assert load_manifest(str(csv_file)) == []


# ---------------------------------------------------------------------------
# run — full pipeline with mocked API
# ---------------------------------------------------------------------------


class TestRunPipeline:
    """Tests for generate_2d.run end-to-end flow."""

    @patch("generate_2d.generate_image", return_value=b"\x89PNG fake")
    def test_run_processes_manifest(self, mock_gen, tmp_path: Path):
        csv_file = tmp_path / "manifest.csv"
        csv_file.write_text(
            "name,prompt,source\nSprite X,a sprite,sdxl\n",
            encoding="utf-8",
        )
        args = _make_args(
            manifest=str(csv_file),
            output_dir=str(tmp_path / "out"),
        )
        run(args)

        assert (tmp_path / "out" / "sprite_x.png").exists()
        mock_gen.assert_called_once()

    @patch("generate_2d.generate_image")
    def test_run_empty_manifest_no_errors(self, mock_gen, tmp_path: Path):
        csv_file = tmp_path / "manifest.csv"
        csv_file.write_text("name,prompt,source\n", encoding="utf-8")
        args = _make_args(
            manifest=str(csv_file),
            output_dir=str(tmp_path / "out"),
        )
        run(args)
        mock_gen.assert_not_called()


# ---------------------------------------------------------------------------
# generate_image — API call with mock
# ---------------------------------------------------------------------------


class TestGenerateImage:
    """Tests for generate_2d.generate_image API call."""

    @patch("generate_2d.requests.post")
    def test_success_returns_png_bytes(self, mock_post):
        import base64
        fake_png = b"\x89PNG fake image"
        mock_resp = MagicMock()
        mock_resp.json.return_value = {"images": [base64.b64encode(fake_png).decode()]}
        mock_resp.raise_for_status = MagicMock()
        mock_post.return_value = mock_resp

        result = generate_image(
            prompt="a sprite", negative_prompt="blurry",
            steps=30, cfg_scale=7.5, width=512, height=512,
            base_url="http://fake:7860",
        )
        assert result == fake_png

    @patch("generate_2d.requests.post")
    def test_no_images_raises_runtime_error(self, mock_post):
        mock_resp = MagicMock()
        mock_resp.json.return_value = {"images": []}
        mock_resp.raise_for_status = MagicMock()
        mock_post.return_value = mock_resp

        with pytest.raises(RuntimeError, match="no images"):
            generate_image(
                prompt="a sprite", negative_prompt="blurry",
                steps=30, cfg_scale=7.5, width=512, height=512,
                base_url="http://fake:7860",
            )

    @patch("generate_2d.requests.post")
    def test_request_failure_raises(self, mock_post):
        import requests as req
        mock_post.side_effect = req.RequestException("connection refused")
        with pytest.raises(RuntimeError, match="SDXL API request failed"):
            generate_image(
                prompt="a sprite", negative_prompt="blurry",
                steps=30, cfg_scale=7.5, width=512, height=512,
                base_url="http://fake:7860",
            )
