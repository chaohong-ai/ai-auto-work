"""
generate_3d.py - Batch 3D model generation via Tripo API.

Reads a CSV manifest, filters rows where source == 'tripo', and submits
generation jobs to the Tripo API. Polls for completion and downloads GLB results.
"""

import argparse
import csv
import os
import sys
import time
from pathlib import Path

import requests
from tqdm import tqdm


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

TRIPO_API_BASE = "https://api.tripo3d.ai/v2/openapi"
DEFAULT_MANIFEST = "asset_manifest.csv"
DEFAULT_OUTPUT_DIR = "output/3d"
DEFAULT_POLL_INTERVAL = 5   # seconds between status polls
DEFAULT_MAX_WAIT = 300      # seconds before a job is considered timed-out


# ---------------------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------------------

def create_tripo_task(prompt: str, api_key: str) -> str:
    """Submit a text-to-3D task and return the task_id.

    Calls POST /task with type "text_to_model".
    """
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "type": "text_to_model",
        "prompt": prompt,
    }
    try:
        response = requests.post(f"{TRIPO_API_BASE}/task", json=payload, headers=headers, timeout=30)
        response.raise_for_status()
        return response.json()["data"]["task_id"]
    except requests.RequestException as exc:
        raise RuntimeError(f"Failed to create Tripo task: {exc}") from exc


def poll_tripo_task(task_id: str, api_key: str) -> dict:
    """Poll a task until it reaches a terminal state and return the result dict.

    Terminal states: 'success', 'failed', 'cancelled'.
    """
    headers = {"Authorization": f"Bearer {api_key}"}

    deadline = time.time() + DEFAULT_MAX_WAIT
    while time.time() < deadline:
        try:
            response = requests.get(f"{TRIPO_API_BASE}/task/{task_id}", headers=headers, timeout=15)
            response.raise_for_status()
        except requests.RequestException as exc:
            print(f"     [warn] Poll request failed: {exc}. Retrying...")
            time.sleep(DEFAULT_POLL_INTERVAL)
            continue
        data = response.json()["data"]
        status = data["status"]
        print(f"     Status: {status}")
        if status == "success":
            return data
        if status in ("failed", "cancelled"):
            raise RuntimeError(f"Task {task_id} ended with status: {status}")
        time.sleep(DEFAULT_POLL_INTERVAL)
    raise TimeoutError(f"Task {task_id} did not complete within {DEFAULT_MAX_WAIT}s")


def download_model(url: str, dest_path: Path) -> None:
    """Download a GLB model file from a URL to dest_path.

    Streams the download and verifies content length when available.
    """
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with requests.get(url, stream=True, timeout=120) as r:
            r.raise_for_status()
            expected_size = int(r.headers.get("content-length", 0))
            downloaded = 0
            with open(dest_path, "wb") as f:
                for chunk in r.iter_content(chunk_size=8192):
                    f.write(chunk)
                    downloaded += len(chunk)
            if expected_size and downloaded != expected_size:
                print(f"  [warn] Expected {expected_size} bytes but downloaded {downloaded} bytes.")
        print(f"  Downloaded -> {dest_path} ({downloaded} bytes)")
    except requests.RequestException as exc:
        raise RuntimeError(f"Failed to download model from {url}: {exc}") from exc


# ---------------------------------------------------------------------------
# Core pipeline
# ---------------------------------------------------------------------------

def load_manifest(manifest_path: str) -> list[dict]:
    """Read the CSV manifest and return rows where source == 'tripo'."""
    rows = []
    with open(manifest_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("source", "").strip().lower() == "tripo":
                rows.append(row)
    return rows


def process_row(row: dict, output_dir: Path, api_key: str, dry_run: bool) -> dict:
    """Generate a single 3D asset from one manifest row. Returns a result dict."""
    name = row["name"]
    prompt = row["prompt"]
    safe_name = name.lower().replace(" ", "_")
    dest_path = output_dir / f"{safe_name}.glb"

    print(f"[3D] Processing: {name!r}")
    print(f"     Prompt: {prompt!r}")

    if dry_run:
        print("     [dry-run] Skipping API call.")
        return {"name": name, "status": "dry-run", "path": str(dest_path)}

    try:
        task_id = create_tripo_task(prompt, api_key)
        print(f"     Task ID: {task_id}")

        result = poll_tripo_task(task_id, api_key)
        model_url = result.get("model_url", "")

        download_model(model_url, dest_path)
        return {"name": name, "status": "success", "path": str(dest_path), "task_id": task_id}

    except Exception as exc:
        print(f"     ERROR: {exc}", file=sys.stderr)
        return {"name": name, "status": "error", "error": str(exc)}


def run(args: argparse.Namespace) -> None:
    api_key = args.api_key or os.environ.get("TRIPO_API_KEY", "")
    if not api_key and not args.dry_run:
        print("ERROR: Tripo API key required. Use --api-key or set TRIPO_API_KEY.", file=sys.stderr)
        sys.exit(1)

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    rows = load_manifest(args.manifest)
    if not rows:
        print("No 3D assets found in manifest (source == 'tripo').")
        return

    print(f"Found {len(rows)} 3D asset(s) to generate.")

    results = []
    for row in tqdm(rows, desc="Generating 3D assets"):
        result = process_row(row, output_dir, api_key, args.dry_run)
        results.append(result)

    # Summary
    success = sum(1 for r in results if r["status"] in ("success", "dry-run"))
    errors = len(results) - success
    print(f"\nDone. {success} succeeded, {errors} failed.")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Batch 3D model generation via Tripo API.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--manifest",
        default=DEFAULT_MANIFEST,
        help="Path to the asset manifest CSV file.",
    )
    parser.add_argument(
        "--output-dir",
        default=DEFAULT_OUTPUT_DIR,
        help="Directory where generated GLB files will be saved.",
    )
    parser.add_argument(
        "--api-key",
        default=None,
        help="Tripo API key (falls back to TRIPO_API_KEY env var).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Parse the manifest and print actions without calling the API.",
    )
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    run(args)


if __name__ == "__main__":
    main()
