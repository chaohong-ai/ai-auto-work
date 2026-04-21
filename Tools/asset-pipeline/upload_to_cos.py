"""
upload_to_cos.py - Batch upload of generated assets to Tencent Cloud COS.

Uses boto3 (S3-compatible API) to upload files found in the output directory
to the configured COS bucket. Updates a local upload manifest JSON on success.
"""

import argparse
import json
import os
import sys
from pathlib import Path

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from tqdm import tqdm


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Tencent COS S3-compatible endpoint pattern:
#   https://{bucket}.cos.{region}.myqcloud.com
# Pass via --endpoint or COS_ENDPOINT env var.
DEFAULT_ENDPOINT = "https://cos.ap-guangzhou.myqcloud.com"
DEFAULT_ASSET_ROOT = "output"
DEFAULT_UPLOAD_LOG = "output/upload_log.json"

# Supported file extensions and their MIME types
MIME_MAP = {
    ".glb": "model/gltf-binary",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".mp3": "audio/mpeg",
    ".ogg": "audio/ogg",
    ".wav": "audio/wav",
}


# ---------------------------------------------------------------------------
# COS helpers
# ---------------------------------------------------------------------------

def build_s3_client(endpoint: str, access_key: str, secret_key: str, region: str):
    """Create a boto3 S3 client configured for Tencent COS.

    Tencent COS is S3-compatible and uses the same endpoint pattern:
      https://cos.{region}.myqcloud.com
    """
    try:
        client = boto3.client(
            "s3",
            endpoint_url=endpoint,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            region_name=region,
        )
        return client
    except (BotoCoreError, ClientError) as exc:
        raise RuntimeError(f"Failed to create COS client: {exc}") from exc


def upload_file(client, local_path: Path, bucket: str, object_key: str, dry_run: bool) -> str:
    """Upload a single file to COS and return its CDN URL.

    Files over 5 GB should use multipart upload (handled automatically by boto3
    upload_file when configured with TransferConfig).
    """
    content_type = MIME_MAP.get(local_path.suffix.lower(), "application/octet-stream")

    if dry_run:
        print(f"  [dry-run] would upload {local_path} -> s3://{bucket}/{object_key}")
        return f"https://{bucket}.cos.{DEFAULT_ENDPOINT.split('cos.')[1] if 'cos.' in DEFAULT_ENDPOINT else 'myqcloud.com'}/{object_key}"

    client.upload_file(
        str(local_path),
        bucket,
        object_key,
        ExtraArgs={"ContentType": content_type, "ACL": "public-read"},
    )

    # Generate CDN URL using the bucket's COS domain
    url = f"https://{bucket}.cos.{client.meta.region_name}.myqcloud.com/{object_key}"
    print(f"  Uploaded {local_path.name} -> {url}")
    return url


# ---------------------------------------------------------------------------
# Core pipeline
# ---------------------------------------------------------------------------

def collect_files(asset_root: Path, extensions: set[str]) -> list[Path]:
    """Recursively collect files under asset_root matching the given extensions."""
    files = []
    for path in sorted(asset_root.rglob("*")):
        if path.is_file() and path.suffix.lower() in extensions:
            files.append(path)
    return files


def derive_object_key(local_path: Path, asset_root: Path, prefix: str) -> str:
    """Convert a local file path to a COS object key.

    Example: output/2d/green_slime.png -> assets/2d/green_slime.png
    """
    relative = local_path.relative_to(asset_root)
    key = f"{prefix.rstrip('/')}/{relative.as_posix()}" if prefix else relative.as_posix()
    return key


def copy_to_local(local_path: Path, local_dir: Path, object_key: str) -> str:
    """Copy a file to local storage directory instead of uploading to COS.

    Used in test environment to avoid COS dependency.
    """
    dest = local_dir / object_key
    dest.parent.mkdir(parents=True, exist_ok=True)
    import shutil
    shutil.copy2(local_path, dest)
    url = f"file://{dest.resolve()}"
    print(f"  [local] {local_path.name} -> {dest}")
    return url


def run(args: argparse.Namespace) -> None:
    is_local = args.local
    access_key = args.access_key or os.environ.get("COS_ACCESS_KEY", "")
    secret_key = args.secret_key or os.environ.get("COS_SECRET_KEY", "")

    if not is_local and not args.dry_run and (not access_key or not secret_key):
        print("ERROR: COS credentials required. Use --access-key/--secret-key or env vars.", file=sys.stderr)
        print("       Or use --local to save to local directory instead.", file=sys.stderr)
        sys.exit(1)

    asset_root = Path(args.asset_root)
    if not asset_root.exists():
        print(f"ERROR: Asset root does not exist: {asset_root}", file=sys.stderr)
        sys.exit(1)

    extensions = set(MIME_MAP.keys())
    files = collect_files(asset_root, extensions)
    if not files:
        print("No uploadable files found.")
        return

    if is_local:
        local_dir = Path(args.local_dir)
        print(f"Found {len(files)} file(s) to save to local dir '{local_dir}'.")
    else:
        print(f"Found {len(files)} file(s) to upload to bucket '{args.bucket}'.")

    client = None
    if not is_local and not args.dry_run:
        client = build_s3_client(args.endpoint, access_key, secret_key, args.region)

    upload_log: list[dict] = []
    desc = "Saving locally" if is_local else "Uploading to COS"
    for local_path in tqdm(files, desc=desc):
        object_key = derive_object_key(local_path, asset_root, args.prefix)
        try:
            if is_local:
                url = copy_to_local(local_path, Path(args.local_dir), object_key)
            else:
                url = upload_file(client, local_path, args.bucket, object_key, args.dry_run)
            upload_log.append({
                "local_path": str(local_path),
                "object_key": object_key,
                "url": url,
                "status": "success",
            })
        except (BotoCoreError, ClientError, Exception) as exc:
            print(f"  ERROR uploading {local_path.name}: {exc}", file=sys.stderr)
            upload_log.append({
                "local_path": str(local_path),
                "object_key": object_key,
                "status": "error",
                "error": str(exc),
            })

    log_path = Path(args.upload_log)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(json.dumps(upload_log, indent=2, ensure_ascii=False), encoding="utf-8")

    success = sum(1 for e in upload_log if e["status"] == "success")
    errors = len(upload_log) - success
    print(f"\nDone. {success} uploaded, {errors} failed.")
    print(f"Upload log saved -> {log_path}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Batch upload generated assets to Tencent Cloud COS.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--asset-root", default=DEFAULT_ASSET_ROOT, help="Root directory of generated assets.")
    parser.add_argument("--bucket", required=True, help="COS bucket name (e.g. my-game-assets-1234567890).")
    parser.add_argument("--region", default="ap-guangzhou", help="COS bucket region.")
    parser.add_argument("--endpoint", default=DEFAULT_ENDPOINT, help="COS S3-compatible endpoint URL.")
    parser.add_argument("--prefix", default="assets", help="Object key prefix inside the bucket.")
    parser.add_argument("--access-key", default=None, help="Tencent Cloud SecretId (falls back to COS_ACCESS_KEY).")
    parser.add_argument("--secret-key", default=None, help="Tencent Cloud SecretKey (falls back to COS_SECRET_KEY).")
    parser.add_argument("--upload-log", default=DEFAULT_UPLOAD_LOG, help="Path to write upload log JSON.")
    parser.add_argument("--local", action="store_true", help="Save to local directory instead of uploading to COS (test mode).")
    parser.add_argument("--local-dir", default="output/storage", help="Local directory for --local mode.")
    parser.add_argument("--dry-run", action="store_true")
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    run(args)


if __name__ == "__main__":
    main()
