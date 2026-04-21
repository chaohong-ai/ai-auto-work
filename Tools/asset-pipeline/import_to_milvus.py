"""
import_to_milvus.py - Import CLIP embedding vectors into Milvus.

Reads the embeddings JSON produced by compute_embeddings.py and inserts
each vector into the configured Milvus collection. Stores the asset name
and type alongside the vector for retrieval.
"""

import argparse
import json
import os
import sys
from pathlib import Path

from pymilvus import (
    Collection,
    CollectionSchema,
    DataType,
    FieldSchema,
    MilvusClient,
    connections,
    utility,
)
from tqdm import tqdm


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DEFAULT_MILVUS_HOST = "localhost"
DEFAULT_MILVUS_PORT = 19530
DEFAULT_EMBEDDINGS_FILE = "output/embeddings.json"
DEFAULT_COLLECTION_NAME = "game_assets"
EMBEDDING_DIM = 512   # ViT-B/32 output dimension; change to 768 for ViT-L/14
INDEX_TYPE = "IVF_FLAT"
METRIC_TYPE = "IP"    # Inner Product (cosine similarity when vectors are normalized)
INDEX_PARAMS = {"nlist": 128}
SEARCH_PARAMS = {"nprobe": 10}


# ---------------------------------------------------------------------------
# Milvus helpers
# ---------------------------------------------------------------------------

def connect_milvus(host: str, port: int) -> None:
    """Establish a connection to Milvus."""
    try:
        connections.connect("default", host=host, port=str(port))
        print(f"Connected to Milvus at {host}:{port}")
    except Exception as exc:
        raise RuntimeError(f"Failed to connect to Milvus at {host}:{port}: {exc}") from exc


def ensure_collection(collection_name: str, dim: int) -> Collection:
    """Create the collection if it does not exist, then return it.

    Schema:
      - id          : auto-generated INT64 primary key
      - name        : VARCHAR (asset name, for display)
      - asset_type  : VARCHAR (3d_model / 2d_sprite / audio_sfx)
      - embedding   : FLOAT_VECTOR(dim)
    """
    if utility.has_collection(collection_name):
        print(f"Collection '{collection_name}' already exists. Reusing.")
        return Collection(collection_name)

    fields = [
        FieldSchema(name="id", dtype=DataType.INT64, is_primary=True, auto_id=True),
        FieldSchema(name="name", dtype=DataType.VARCHAR, max_length=256),
        FieldSchema(name="asset_type", dtype=DataType.VARCHAR, max_length=64),
        FieldSchema(name="embedding", dtype=DataType.FLOAT_VECTOR, dim=dim),
    ]
    schema = CollectionSchema(fields, description="Game asset CLIP embeddings")
    collection = Collection(collection_name, schema)

    # Build index on the vector field
    collection.create_index(
        field_name="embedding",
        index_params={"index_type": INDEX_TYPE, "metric_type": METRIC_TYPE, "params": INDEX_PARAMS},
    )
    print(f"Collection '{collection_name}' created with {INDEX_TYPE} index.")
    return collection


# ---------------------------------------------------------------------------
# Core pipeline
# ---------------------------------------------------------------------------

def load_embeddings(embeddings_file: str) -> list[dict]:
    path = Path(embeddings_file)
    if not path.exists():
        print(f"ERROR: Embeddings file not found: {embeddings_file}", file=sys.stderr)
        sys.exit(1)
    data = json.loads(path.read_text(encoding="utf-8"))
    # Filter out rows that were skipped during embedding computation
    valid = [e for e in data if "embedding" in e]
    skipped = len(data) - len(valid)
    if skipped:
        print(f"[warn] Skipping {skipped} entry/entries without embeddings.")
    return valid


def run(args: argparse.Namespace) -> None:
    host = args.host or os.environ.get("MILVUS_HOST", DEFAULT_MILVUS_HOST)
    port = args.port or int(os.environ.get("MILVUS_PORT", DEFAULT_MILVUS_PORT))

    entries = load_embeddings(args.embeddings_file)
    if not entries:
        print("No valid embeddings to import.")
        return

    if args.dry_run:
        print(f"[dry-run] Would insert {len(entries)} vector(s) into "
              f"collection '{args.collection}'.")
        for e in entries:
            print(f"  - {e['name']} ({e.get('type', '?')}) dim={len(e['embedding'])}")
        return

    connect_milvus(host, port)
    collection = ensure_collection(args.collection, EMBEDDING_DIM)

    # Prepare data columns for batch insert
    names = [e["name"] for e in entries]
    asset_types = [e.get("type", "unknown") for e in entries]
    embeddings = [e["embedding"] for e in entries]

    # Chunk large imports to avoid memory issues
    CHUNK_SIZE = 10000
    total_inserted = 0
    for i in range(0, len(names), CHUNK_SIZE):
        chunk_names = names[i:i + CHUNK_SIZE]
        chunk_types = asset_types[i:i + CHUNK_SIZE]
        chunk_embeddings = embeddings[i:i + CHUNK_SIZE]
        data = [chunk_names, chunk_types, chunk_embeddings]
        try:
            result = collection.insert(data)
            total_inserted += result.insert_count
            print(f"  Inserted chunk {i // CHUNK_SIZE + 1}: {result.insert_count} vector(s)")
        except Exception as exc:
            print(f"  ERROR inserting chunk at offset {i}: {exc}", file=sys.stderr)

    collection.flush()
    print(f"Inserted {total_inserted} vector(s) into '{args.collection}'.")

    # Load collection into memory for queries
    collection.load()
    print(f"Collection '{args.collection}' loaded into memory and ready for search.")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Import CLIP embedding vectors into Milvus.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--embeddings-file", default=DEFAULT_EMBEDDINGS_FILE, help="Path to embeddings JSON file.")
    parser.add_argument("--collection", default=DEFAULT_COLLECTION_NAME, help="Milvus collection name.")
    parser.add_argument("--host", default=None, help="Milvus host (falls back to MILVUS_HOST env var).")
    parser.add_argument("--port", type=int, default=None, help="Milvus port (falls back to MILVUS_PORT env var).")
    parser.add_argument("--dry-run", action="store_true")
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    run(args)


if __name__ == "__main__":
    main()
