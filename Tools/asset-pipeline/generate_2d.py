"""
generate_2d.py - Batch 2D sprite generation via a self-hosted SDXL API.

Reads a CSV manifest, filters rows where source == 'sdxl', and submits
image generation requests. Saves PNG results to the output directory.
"""

import argparse
import base64
import csv
import os
import sys
from pathlib import Path

import requests
from tqdm import tqdm


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DEFAULT_SDXL_URL = "http://localhost:7860"  # ComfyUI / A1111 base URL
DEFAULT_MANIFEST = "asset_manifest.csv"
DEFAULT_OUTPUT_DIR = "output/2d"
DEFAULT_STEPS = 30
DEFAULT_CFG_SCALE = 7.5
DEFAULT_WIDTH = 512
DEFAULT_HEIGHT = 512
DEFAULT_NEGATIVE_PROMPT = (
    "blurry, low quality, watermark, text, signature, duplicate, ugly"
)


# ---------------------------------------------------------------------------
# API helpers (A1111-compatible txt2img endpoint)
# ---------------------------------------------------------------------------

def generate_image(
    prompt: str,
    negative_prompt: str,
    steps: int,
    cfg_scale: float,
    width: int,
    height: int,
    base_url: str,
) -> bytes:
    """Call the SDXL txt2img API and return raw PNG bytes.

    Uses the Automatic1111 (A1111) compatible API format.
    """
    endpoint = f"{base_url.rstrip('/')}/sdapi/v1/txt2img"
    payload = {
        "prompt": prompt,
        "negative_prompt": negative_prompt,
        "steps": steps,
        "cfg_scale": cfg_scale,
        "width": width,
        "height": height,
        "sampler_name": "DPM++ 2M Karras",
    }

    try:
        response = requests.post(endpoint, json=payload, timeout=120)
        response.raise_for_status()
        result = response.json()
        if "images" not in result or not result["images"]:
            raise RuntimeError("SDXL API returned no images in response.")
        b64_image = result["images"][0]
        return base64.b64decode(b64_image)
    except requests.RequestException as exc:
        raise RuntimeError(f"SDXL API request failed: {exc}") from exc


# ---------------------------------------------------------------------------
# Core pipeline
# ---------------------------------------------------------------------------

def load_manifest(manifest_path: str) -> list[dict]:
    """Read the CSV manifest and return rows where source == 'sdxl'."""
    rows = []
    with open(manifest_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("source", "").strip().lower() == "sdxl":
                rows.append(row)
    return rows


def process_row(row: dict, output_dir: Path, base_url: str, args: argparse.Namespace) -> dict:
    """Generate a single 2D sprite from one manifest row. Returns a result dict."""
    name = row["name"]
    prompt = row["prompt"]
    safe_name = name.lower().replace(" ", "_")
    dest_path = output_dir / f"{safe_name}.png"

    print(f"[2D] Processing: {name!r}")
    print(f"     Prompt: {prompt!r}")

    if args.dry_run:
        print("     [dry-run] Skipping API call.")
        return {"name": name, "status": "dry-run", "path": str(dest_path)}

    try:
        png_bytes = generate_image(
            prompt=prompt,
            negative_prompt=args.negative_prompt,
            steps=args.steps,
            cfg_scale=args.cfg_scale,
            width=args.width,
            height=args.height,
            base_url=base_url,
        )
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        dest_path.write_bytes(png_bytes)
        print(f"     Saved -> {dest_path}")
        return {"name": name, "status": "success", "path": str(dest_path)}

    except Exception as exc:
        print(f"     ERROR: {exc}", file=sys.stderr)
        return {"name": name, "status": "error", "error": str(exc)}


def run(args: argparse.Namespace) -> None:
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    rows = load_manifest(args.manifest)
    if not rows:
        print("No 2D assets found in manifest (source == 'sdxl').")
        return

    print(f"Found {len(rows)} 2D asset(s) to generate.")

    results = []
    for row in tqdm(rows, desc="Generating 2D sprites"):
        result = process_row(row, output_dir, args.sdxl_url, args)
        results.append(result)

    success = sum(1 for r in results if r["status"] in ("success", "dry-run"))
    errors = len(results) - success
    print(f"\nDone. {success} succeeded, {errors} failed.")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Batch 2D sprite generation via self-hosted SDXL API.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--manifest", default=DEFAULT_MANIFEST)
    parser.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--sdxl-url", default=DEFAULT_SDXL_URL, help="Base URL of the SDXL API server.")
    parser.add_argument("--steps", type=int, default=DEFAULT_STEPS)
    parser.add_argument("--cfg-scale", type=float, default=DEFAULT_CFG_SCALE)
    parser.add_argument("--width", type=int, default=DEFAULT_WIDTH)
    parser.add_argument("--height", type=int, default=DEFAULT_HEIGHT)
    parser.add_argument("--negative-prompt", default=DEFAULT_NEGATIVE_PROMPT)
    parser.add_argument("--dry-run", action="store_true")
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    run(args)


if __name__ == "__main__":
    main()
