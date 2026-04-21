"""
import_to_mongo.py - Import asset metadata into MongoDB.

Reads the asset manifest CSV together with the COS upload log, merges the
data, and upserts documents into the configured MongoDB collection.
"""

import argparse
import csv
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

from pymongo import MongoClient, UpdateOne
from pymongo.errors import BulkWriteError, ConnectionFailure
from tqdm import tqdm


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DEFAULT_MONGO_URI = "mongodb://localhost:27017"
DEFAULT_DB_NAME = "gamemaker"
DEFAULT_COLLECTION = "assets"
DEFAULT_MANIFEST = "asset_manifest.csv"
DEFAULT_UPLOAD_LOG = "output/upload_log.json"


# ---------------------------------------------------------------------------
# Data helpers
# ---------------------------------------------------------------------------

def load_manifest(manifest_path: str) -> list[dict]:
    with open(manifest_path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def load_upload_log(upload_log_path: str) -> dict[str, str]:
    """Load the upload log and return a mapping of local filename -> COS URL."""
    path = Path(upload_log_path)
    if not path.exists():
        print(f"[warn] Upload log not found at {upload_log_path}. COS URLs will be empty.")
        return {}
    entries = json.loads(path.read_text(encoding="utf-8"))
    return {Path(e["local_path"]).name: e.get("url", "") for e in entries if e.get("status") == "success"}


def build_document(row: dict, url_map: dict[str, str], now: datetime) -> dict:
    """Construct a MongoDB document from a manifest row."""
    safe_name = row["name"].lower().replace(" ", "_")
    asset_type = row.get("type", "")

    # Derive the expected filename for this asset type
    ext_map = {"3d_model": ".glb", "2d_sprite": ".png", "audio_sfx": ".mp3"}
    ext = ext_map.get(asset_type, "")
    filename = f"{safe_name}{ext}"
    cos_url = url_map.get(filename, "")

    tags = [t.strip() for t in row.get("tags", "").split(",") if t.strip()]

    return {
        "name": row["name"],
        "description": row.get("description", ""),
        "type": asset_type,
        "category": row.get("category", ""),
        "subcategory": row.get("subcategory", ""),
        "tags": tags,
        "style": row.get("style", ""),
        "source": row.get("source", ""),
        "prompt": row.get("prompt", ""),
        "cos_url": cos_url,
        "created_at": now,
        "updated_at": now,
        "version": 1,
    }


# ---------------------------------------------------------------------------
# Core pipeline
# ---------------------------------------------------------------------------

def run(args: argparse.Namespace) -> None:
    mongo_uri = args.mongo_uri or os.environ.get("MONGO_URI", DEFAULT_MONGO_URI)

    rows = load_manifest(args.manifest)
    url_map = load_upload_log(args.upload_log)

    if not rows:
        print("Manifest is empty. Nothing to import.")
        return

    now = datetime.now(tz=timezone.utc)
    documents = [build_document(row, url_map, now) for row in rows]

    if args.dry_run:
        print(f"[dry-run] Would upsert {len(documents)} document(s) into "
              f"{args.db_name}.{args.collection}.")
        for doc in documents:
            print(f"  - {doc['name']} ({doc['type']}) -> {doc['cos_url'] or '(no URL)'}")
        return

    try:
        client = MongoClient(mongo_uri, serverSelectionTimeoutMS=5000)
        # Force connection check
        client.admin.command("ping")
    except ConnectionFailure as exc:
        print(f"ERROR: Cannot connect to MongoDB at {mongo_uri}: {exc}", file=sys.stderr)
        sys.exit(1)

    db = client[args.db_name]
    collection = db[args.collection]

    # Create indexes if they don't already exist
    existing_indexes = {idx["name"] for idx in collection.list_indexes()}
    if "name_1" not in existing_indexes:
        collection.create_index("name", unique=True)
        print("Created unique index on 'name'.")
    if "tags_1" not in existing_indexes:
        collection.create_index("tags")
        print("Created index on 'tags'.")
    if "type_1" not in existing_indexes:
        collection.create_index("type")
        print("Created index on 'type'.")

    operations = [
        UpdateOne(
            {"name": doc["name"]},
            {"$set": doc, "$setOnInsert": {"created_at": now}},
            upsert=True,
        )
        for doc in documents
    ]

    try:
        result = collection.bulk_write(operations, ordered=False)
        print(f"Upserted {result.upserted_count} new, modified {result.modified_count} existing document(s).")
    except BulkWriteError as exc:
        print(f"Bulk write error: {exc.details}", file=sys.stderr)
        sys.exit(1)
    finally:
        client.close()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Import asset metadata into MongoDB.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--manifest", default=DEFAULT_MANIFEST)
    parser.add_argument("--upload-log", default=DEFAULT_UPLOAD_LOG, help="Path to the COS upload log JSON.")
    parser.add_argument("--mongo-uri", default=None, help="MongoDB connection URI (falls back to MONGO_URI env var).")
    parser.add_argument("--db-name", default=DEFAULT_DB_NAME)
    parser.add_argument("--collection", default=DEFAULT_COLLECTION)
    parser.add_argument("--dry-run", action="store_true")
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    run(args)


if __name__ == "__main__":
    main()
