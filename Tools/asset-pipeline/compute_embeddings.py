"""
compute_embeddings.py - Batch CLIP embedding computation for generated assets.

Calls the local CLIP service (clip-service/main.py) for each asset file,
then saves the resulting embedding vectors as a JSON file for later import
into Milvus.
"""

import argparse
import csv
import json
import os
import sys
from pathlib import Path

import requests
from tqdm import tqdm


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

CLIP_SERVICE_URL = "http://localhost:8000"
DEFAULT_MANIFEST = "asset_manifest.csv"
DEFAULT_ASSET_ROOT = "output"
DEFAULT_OUTPUT_FILE = "output/embeddings.json"

# Extension map for locating generated files by asset type
ASSET_TYPE_EXT = {
    "3d_model": ("3d", ".glb"),
    "2d_sprite": ("2d", ".png"),
    "audio_sfx": ("audio", ".mp3"),
}


# ---------------------------------------------------------------------------
# CLIP service helpers
# ---------------------------------------------------------------------------

def embed_text(text: str, base_url: str, max_retries: int = 3) -> list[float]:
    """Call /embed/text on the CLIP service and return the embedding vector."""
    endpoint = f"{base_url.rstrip('/')}/embed/text"
    for attempt in range(1, max_retries + 1):
        try:
            response = requests.post(endpoint, json={"text": text}, timeout=30)
            response.raise_for_status()
            return response.json()["embedding"]
        except requests.RequestException as exc:
            if attempt == max_retries:
                raise RuntimeError(f"Failed to embed text after {max_retries} attempts: {exc}") from exc
            print(f"  [warn] embed_text attempt {attempt} failed: {exc}. Retrying...")


def embed_image(image_path: Path, base_url: str, max_retries: int = 3) -> list[float]:
    """Call /embed/image on the CLIP service and return the embedding vector."""
    endpoint = f"{base_url.rstrip('/')}/embed/image"
    for attempt in range(1, max_retries + 1):
        try:
            with open(image_path, "rb") as f:
                response = requests.post(endpoint, files={"file": f}, timeout=30)
            response.raise_for_status()
            return response.json()["embedding"]
        except requests.RequestException as exc:
            if attempt == max_retries:
                raise RuntimeError(f"Failed to embed image after {max_retries} attempts: {exc}") from exc
            print(f"  [warn] embed_image attempt {attempt} failed: {exc}. Retrying...")


# ---------------------------------------------------------------------------
# Core pipeline
# ---------------------------------------------------------------------------

def load_manifest(manifest_path: str) -> list[dict]:
    with open(manifest_path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def resolve_asset_path(row: dict, asset_root: Path) -> Path | None:
    """Derive the expected file path for a manifest row's generated asset."""
    asset_type = row.get("type", "").strip()
    if asset_type not in ASSET_TYPE_EXT:
        return None
    subdir, ext = ASSET_TYPE_EXT[asset_type]
    safe_name = row["name"].lower().replace(" ", "_")
    return asset_root / subdir / f"{safe_name}{ext}"


def compute_embedding_for_row(
    row: dict,
    asset_root: Path,
    clip_url: str,
    use_text_fallback: bool,
) -> dict:
    """Compute CLIP embedding for a single asset row.

    For image assets: embed the image file.
    For audio / 3D assets (no direct CLIP support): embed the text prompt.
    Falls back to text embedding if the file is missing and use_text_fallback is True.
    """
    name = row["name"]
    prompt = row.get("prompt", "")
    asset_type = row.get("type", "")
    asset_path = resolve_asset_path(row, asset_root)

    # Audio and 3D models: use text prompt embedding
    if asset_type in ("audio_sfx", "3d_model"):
        vector = embed_text(prompt, clip_url)
        return {
            "name": name,
            "type": asset_type,
            "embed_source": "text",
            "embedding": vector,
            "metadata": {k: v for k, v in row.items() if k != "embedding"},
        }

    # 2D sprites: prefer image embedding
    if asset_path and asset_path.exists():
        vector = embed_image(asset_path, clip_url)
        return {
            "name": name,
            "type": asset_type,
            "embed_source": "image",
            "embedding": vector,
            "metadata": {k: v for k, v in row.items() if k != "embedding"},
        }

    if use_text_fallback:
        print(f"  [warn] {name!r}: image not found at {asset_path}, using text fallback.")
        vector = embed_text(prompt, clip_url)
        return {
            "name": name,
            "type": asset_type,
            "embed_source": "text_fallback",
            "embedding": vector,
            "metadata": {k: v for k, v in row.items() if k != "embedding"},
        }

    return {"name": name, "type": asset_type, "status": "skipped", "reason": "file not found"}


def run(args: argparse.Namespace) -> None:
    asset_root = Path(args.asset_root)
    output_file = Path(args.output_file)
    output_file.parent.mkdir(parents=True, exist_ok=True)

    rows = load_manifest(args.manifest)
    if not rows:
        print("Manifest is empty.")
        return

    print(f"Computing embeddings for {len(rows)} asset(s) via {args.clip_url} ...")

    results = []
    for row in tqdm(rows, desc="Embedding assets"):
        result = compute_embedding_for_row(row, asset_root, args.clip_url, args.text_fallback)
        results.append(result)

    output_file.write_text(json.dumps(results, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\nEmbeddings saved -> {output_file}")

    skipped = sum(1 for r in results if r.get("status") == "skipped")
    print(f"Processed: {len(results) - skipped}, Skipped: {skipped}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Batch CLIP embedding computation for generated assets.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--manifest", default=DEFAULT_MANIFEST)
    parser.add_argument("--asset-root", default=DEFAULT_ASSET_ROOT, help="Root directory containing generated asset subdirs.")
    parser.add_argument("--output-file", default=DEFAULT_OUTPUT_FILE, help="Path for the output embeddings JSON file.")
    parser.add_argument("--clip-url", default=CLIP_SERVICE_URL, help="Base URL of the CLIP service.")
    parser.add_argument(
        "--text-fallback",
        action="store_true",
        help="Fall back to text-prompt embedding when the image file is missing.",
    )
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    run(args)


if __name__ == "__main__":
    main()
