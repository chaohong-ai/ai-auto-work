"""
generate_audio.py - Batch audio SFX generation via ElevenLabs API.

Reads a CSV manifest, filters rows where source == 'elevenlabs', and
submits sound-effect generation requests. Saves MP3 results to the
output directory.
"""

import argparse
import csv
import os
import sys
from pathlib import Path

import requests
from tqdm import tqdm


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

ELEVENLABS_API_BASE = "https://api.elevenlabs.io/v1"
DEFAULT_MANIFEST = "asset_manifest.csv"
DEFAULT_OUTPUT_DIR = "output/audio"
DEFAULT_DURATION_SECONDS = 2.0
DEFAULT_PROMPT_INFLUENCE = 0.3


# ---------------------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------------------

def generate_sfx(
    prompt: str,
    duration_seconds: float,
    prompt_influence: float,
    api_key: str,
) -> bytes:
    """Call ElevenLabs sound-generation endpoint and return raw audio bytes.

    Reference: POST /v1/sound-generation
    """
    endpoint = f"{ELEVENLABS_API_BASE}/sound-generation"
    headers = {
        "xi-api-key": api_key,
        "Content-Type": "application/json",
    }
    payload = {
        "text": prompt,
        "duration_seconds": duration_seconds,
        "prompt_influence": prompt_influence,
    }

    try:
        response = requests.post(endpoint, json=payload, headers=headers, timeout=60)
        response.raise_for_status()
        if not response.content:
            raise RuntimeError("ElevenLabs API returned empty audio content.")
        return response.content  # raw MP3 bytes
    except requests.RequestException as exc:
        raise RuntimeError(f"ElevenLabs API request failed: {exc}") from exc


# ---------------------------------------------------------------------------
# Core pipeline
# ---------------------------------------------------------------------------

def load_manifest(manifest_path: str) -> list[dict]:
    """Read the CSV manifest and return rows where source == 'elevenlabs'."""
    rows = []
    with open(manifest_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("source", "").strip().lower() == "elevenlabs":
                rows.append(row)
    return rows


def process_row(row: dict, output_dir: Path, api_key: str, args: argparse.Namespace) -> dict:
    """Generate a single audio clip from one manifest row. Returns a result dict."""
    name = row["name"]
    prompt = row["prompt"]
    safe_name = name.lower().replace(" ", "_")
    dest_path = output_dir / f"{safe_name}.mp3"

    print(f"[Audio] Processing: {name!r}")
    print(f"        Prompt: {prompt!r}")

    if args.dry_run:
        print("        [dry-run] Skipping API call.")
        return {"name": name, "status": "dry-run", "path": str(dest_path)}

    try:
        audio_bytes = generate_sfx(
            prompt=prompt,
            duration_seconds=args.duration,
            prompt_influence=args.prompt_influence,
            api_key=api_key,
        )
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        dest_path.write_bytes(audio_bytes)
        print(f"        Saved -> {dest_path}")
        return {"name": name, "status": "success", "path": str(dest_path)}

    except Exception as exc:
        print(f"        ERROR: {exc}", file=sys.stderr)
        return {"name": name, "status": "error", "error": str(exc)}


def run(args: argparse.Namespace) -> None:
    api_key = args.api_key or os.environ.get("ELEVENLABS_API_KEY", "")
    if not api_key and not args.dry_run:
        print("ERROR: ElevenLabs API key required. Use --api-key or set ELEVENLABS_API_KEY.", file=sys.stderr)
        sys.exit(1)

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    rows = load_manifest(args.manifest)
    if not rows:
        print("No audio assets found in manifest (source == 'elevenlabs').")
        return

    print(f"Found {len(rows)} audio asset(s) to generate.")

    results = []
    for row in tqdm(rows, desc="Generating audio SFX"):
        result = process_row(row, output_dir, api_key, args)
        results.append(result)

    success = sum(1 for r in results if r["status"] in ("success", "dry-run"))
    errors = len(results) - success
    print(f"\nDone. {success} succeeded, {errors} failed.")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Batch audio SFX generation via ElevenLabs API.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--manifest", default=DEFAULT_MANIFEST)
    parser.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    parser.add_argument(
        "--api-key",
        default=None,
        help="ElevenLabs API key (falls back to ELEVENLABS_API_KEY env var).",
    )
    parser.add_argument(
        "--duration",
        type=float,
        default=DEFAULT_DURATION_SECONDS,
        help="Desired audio duration in seconds.",
    )
    parser.add_argument(
        "--prompt-influence",
        type=float,
        default=DEFAULT_PROMPT_INFLUENCE,
        help="How strongly the text prompt guides generation (0.0 - 1.0).",
    )
    parser.add_argument("--dry-run", action="store_true")
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    run(args)


if __name__ == "__main__":
    main()
