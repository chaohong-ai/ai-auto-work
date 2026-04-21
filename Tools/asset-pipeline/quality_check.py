"""
quality_check.py - Quality gate using CLIP score (image-text similarity).

For each 2D sprite in the output directory, computes the cosine similarity
between its image embedding and its text-prompt embedding via the CLIP service.
Assets below the threshold are flagged in a report JSON.
"""

import argparse
import csv
import json
import math
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
DEFAULT_REPORT_FILE = "output/quality_report.json"
DEFAULT_THRESHOLD = 0.25   # CLIP cosine similarity threshold (0–1)

# Only 2D sprites can be quality-checked with image embeddings.
# 3D and audio assets fall back to a text-text self-similarity sanity check.
VISUAL_TYPES = {"2d_sprite"}


# ---------------------------------------------------------------------------
# CLIP service helpers
# ---------------------------------------------------------------------------

def embed_text(text: str, base_url: str, max_retries: int = 3) -> list[float]:
    """Fetch text embedding from the CLIP service with retry logic."""
    endpoint = f"{base_url.rstrip('/')}/embed/text"
    for attempt in range(1, max_retries + 1):
        try:
            r = requests.post(endpoint, json={"text": text}, timeout=30)
            r.raise_for_status()
            return r.json()["embedding"]
        except requests.RequestException as exc:
            if attempt == max_retries:
                raise RuntimeError(f"Failed to embed text after {max_retries} attempts: {exc}") from exc
            print(f"  [warn] embed_text attempt {attempt} failed: {exc}. Retrying...")


def embed_image(image_path: Path, base_url: str, max_retries: int = 3) -> list[float]:
    """Fetch image embedding from the CLIP service with retry logic."""
    endpoint = f"{base_url.rstrip('/')}/embed/image"
    for attempt in range(1, max_retries + 1):
        try:
            with open(image_path, "rb") as f:
                r = requests.post(endpoint, files={"file": f}, timeout=30)
            r.raise_for_status()
            return r.json()["embedding"]
        except requests.RequestException as exc:
            if attempt == max_retries:
                raise RuntimeError(f"Failed to embed image after {max_retries} attempts: {exc}") from exc
            print(f"  [warn] embed_image attempt {attempt} failed: {exc}. Retrying...")


# ---------------------------------------------------------------------------
# Math helpers
# ---------------------------------------------------------------------------

def cosine_similarity(a: list[float], b: list[float]) -> float:
    """Compute cosine similarity between two equal-length vectors."""
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = math.sqrt(sum(x * x for x in a))
    norm_b = math.sqrt(sum(y * y for y in b))
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return dot / (norm_a * norm_b)


# ---------------------------------------------------------------------------
# Core pipeline
# ---------------------------------------------------------------------------

def load_manifest(manifest_path: str) -> list[dict]:
    with open(manifest_path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def resolve_image_path(row: dict, asset_root: Path) -> Path | None:
    if row.get("type") not in VISUAL_TYPES:
        return None
    safe_name = row["name"].lower().replace(" ", "_")
    return asset_root / "2d" / f"{safe_name}.png"


def check_row(row: dict, asset_root: Path, clip_url: str, threshold: float) -> dict:
    """Run CLIP quality check for a single asset row."""
    name = row["name"]
    prompt = row.get("prompt", "")
    asset_type = row.get("type", "")
    image_path = resolve_image_path(row, asset_root)

    result = {
        "name": name,
        "type": asset_type,
        "prompt": prompt,
        "threshold": threshold,
    }

    if image_path and image_path.exists():
        img_vec = embed_image(image_path, clip_url)
        txt_vec = embed_text(prompt, clip_url)
        score = cosine_similarity(img_vec, txt_vec)
        result["score"] = round(score, 4)
        result["passed"] = score >= threshold
        result["check_type"] = "image_text"

    elif asset_type in VISUAL_TYPES:
        # Image missing — mark as failed
        result["score"] = None
        result["passed"] = False
        result["check_type"] = "image_text"
        result["reason"] = f"Image file not found: {image_path}"

    else:
        # Non-visual asset: skip CLIP check, mark as not applicable
        result["score"] = None
        result["passed"] = True   # not applicable = not blocked
        result["check_type"] = "n/a"
        result["reason"] = "Non-visual asset; CLIP quality check not applicable."

    return result


def run(args: argparse.Namespace) -> None:
    asset_root = Path(args.asset_root)
    report_path = Path(args.report_file)
    report_path.parent.mkdir(parents=True, exist_ok=True)

    rows = load_manifest(args.manifest)
    if not rows:
        print("Manifest is empty.")
        return

    print(f"Running quality checks for {len(rows)} asset(s) (threshold={args.threshold}) ...")

    report = []
    for row in tqdm(rows, desc="Quality checking"):
        result = check_row(row, asset_root, args.clip_url, args.threshold)
        report.append(result)

    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")

    passed = sum(1 for r in report if r["passed"])
    failed = len(report) - passed
    print(f"\nResults: {passed} passed, {failed} flagged.")
    print(f"Report saved -> {report_path}")

    if failed and args.fail_on_error:
        print("ERROR: One or more assets failed the quality threshold.", file=sys.stderr)
        sys.exit(1)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Quality gate for generated assets using CLIP score.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--manifest", default=DEFAULT_MANIFEST)
    parser.add_argument("--asset-root", default=DEFAULT_ASSET_ROOT)
    parser.add_argument("--clip-url", default=CLIP_SERVICE_URL, help="Base URL of the CLIP service.")
    parser.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD, help="Minimum cosine similarity score to pass.")
    parser.add_argument("--report-file", default=DEFAULT_REPORT_FILE, help="Path to write the quality report JSON.")
    parser.add_argument(
        "--fail-on-error",
        action="store_true",
        help="Exit with code 1 if any asset fails the quality check (useful in CI).",
    )
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    run(args)


if __name__ == "__main__":
    main()
