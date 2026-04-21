#!/usr/bin/env bash
# 素材流水线编排：按顺序执行所有素材处理步骤
# 用法: ./orchestrate.sh [--local] [manifest.csv]
#   --local: 保存到本地目录而非上传 COS（测试环境）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_MODE=false

# Parse flags
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --local) LOCAL_MODE=true; shift ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

MANIFEST="${1:-$SCRIPT_DIR/asset_manifest.csv}"

if [ ! -f "$MANIFEST" ]; then
  echo "Error: Manifest file not found: $MANIFEST"
  echo "Usage: $0 [--local] [path/to/asset_manifest.csv]"
  exit 1
fi

echo "=== Asset Pipeline ==="
echo "Manifest: $MANIFEST"
if [ "$LOCAL_MODE" = true ]; then
  echo "Mode: LOCAL (files saved to local directory)"
else
  echo "Mode: COS (files uploaded to Tencent Cloud)"
fi
echo ""

# Step 1: Generate 2D sprites
echo "[1/8] Generating 2D sprites..."
python "$SCRIPT_DIR/generate_2d.py" --manifest "$MANIFEST"
echo "  ✓ 2D generation complete"

# Step 2: Generate 3D models
echo "[2/8] Generating 3D models..."
python "$SCRIPT_DIR/generate_3d.py" --manifest "$MANIFEST"
echo "  ✓ 3D generation complete"

# Step 3: Generate audio
echo "[3/8] Generating audio assets..."
python "$SCRIPT_DIR/generate_audio.py" --manifest "$MANIFEST"
echo "  ✓ Audio generation complete"

# Step 4: Quality check
echo "[4/8] Running quality checks..."
python "$SCRIPT_DIR/quality_check.py" --manifest "$MANIFEST"
echo "  ✓ Quality check complete"

# Step 5: Compute CLIP embeddings
echo "[5/8] Computing CLIP embeddings..."
python "$SCRIPT_DIR/compute_embeddings.py" --manifest "$MANIFEST"
echo "  ✓ Embeddings computed"

# Step 6: Upload to COS or save locally
if [ "$LOCAL_MODE" = true ]; then
  echo "[6/8] Saving to local storage..."
  python "$SCRIPT_DIR/upload_to_cos.py" --local --manifest "$MANIFEST"
  echo "  ✓ Local save complete"
else
  echo "[6/8] Uploading to COS..."
  python "$SCRIPT_DIR/upload_to_cos.py" --manifest "$MANIFEST"
  echo "  ✓ COS upload complete"
fi

# Step 7: Import to MongoDB
echo "[7/8] Importing to MongoDB..."
python "$SCRIPT_DIR/import_to_mongo.py" --manifest "$MANIFEST"
echo "  ✓ MongoDB import complete"

# Step 8: Import to Milvus
echo "[8/8] Importing to Milvus..."
python "$SCRIPT_DIR/import_to_milvus.py" --manifest "$MANIFEST"
echo "  ✓ Milvus import complete"

echo ""
echo "=== Pipeline Complete ==="
