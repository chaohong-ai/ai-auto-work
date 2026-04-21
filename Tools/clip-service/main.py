"""
main.py - FastAPI CLIP embedding service.

Exposes two endpoints:
  POST /embed/text   - Returns a CLIP text embedding for a given string.
  POST /embed/image  - Returns a CLIP image embedding for an uploaded file.

Run with:
  uvicorn main:app --host 0.0.0.0 --port 8000
"""

import base64
import io
import os
from contextlib import asynccontextmanager
from typing import Any

import open_clip
import torch
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from PIL import Image
from pydantic import BaseModel


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Model name and pretrained weights tag.
# ViT-B-32 is a good balance of speed and quality for game asset search.
MODEL_NAME = os.getenv("CLIP_MODEL", "ViT-L-14")
PRETRAINED = os.getenv("CLIP_PRETRAINED", "openai")
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"


# ---------------------------------------------------------------------------
# Global model state (loaded once at startup)
# ---------------------------------------------------------------------------

class _ModelState:
    model: Any = None
    preprocess: Any = None
    tokenizer: Any = None
    milvus: Any = None


_state = _ModelState()


# ---------------------------------------------------------------------------
# Lifespan (replaces deprecated @app.on_event("startup"))
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load the CLIP model during application startup."""
    print(f"Loading CLIP model: {MODEL_NAME} / {PRETRAINED} on {DEVICE} ...")
    _state.model, _, _state.preprocess = open_clip.create_model_and_transforms(
        MODEL_NAME,
        pretrained=PRETRAINED,
        device=DEVICE,
    )
    _state.model.eval()
    _state.tokenizer = open_clip.get_tokenizer(MODEL_NAME)
    print("CLIP model loaded.")

    # Optional Milvus connection for /search endpoint
    milvus_uri = os.getenv("MILVUS_URI")
    if milvus_uri:
        try:
            from pymilvus import MilvusClient
            _state.milvus = MilvusClient(uri=milvus_uri)
            print(f"Connected to Milvus at {milvus_uri}")
        except Exception as exc:
            print(f"Warning: failed to connect to Milvus: {exc}")

    yield
    # Teardown: release GPU memory
    if _state.milvus is not None:
        _state.milvus = None
        print("Milvus client released.")
    if _state.model is not None:
        del _state.model
        del _state.preprocess
        del _state.tokenizer
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
        print("CLIP model unloaded.")


app = FastAPI(
    title="CLIP Embedding Service",
    description="Lightweight FastAPI wrapper around open_clip for game asset search.",
    version="0.1.0",
    lifespan=lifespan,
)


# ---------------------------------------------------------------------------
# Request / response schemas
# ---------------------------------------------------------------------------

class TextEmbedRequest(BaseModel):
    text: str


class Base64ImageRequest(BaseModel):
    image_base64: str


class EmbeddingResponse(BaseModel):
    embedding: list[float]
    model: str
    dim: int


class SearchRequest(BaseModel):
    text: str | None = None
    image_base64: str | None = None
    collection: str = "assets"
    limit: int = 10
    offset: int = 0
    filter_expr: str | None = None


class SearchResult(BaseModel):
    id: str
    score: float
    metadata: dict


class SearchResponse(BaseModel):
    results: list[SearchResult]
    total: int


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _normalize(tensor: torch.Tensor) -> list[float]:
    """L2-normalize a 1-D tensor and return it as a Python list."""
    normed = torch.nn.functional.normalize(tensor, dim=-1)
    return normed.squeeze(0).tolist()


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.get("/health")
async def health() -> dict:
    """Simple liveness probe."""
    return {
        "status": "ok",
        "model": MODEL_NAME,
        "pretrained": PRETRAINED,
        "device": DEVICE,
    }


@app.post("/embed/text", response_model=EmbeddingResponse)
async def embed_text(request: TextEmbedRequest) -> EmbeddingResponse:
    """Return a normalized CLIP text embedding for the given string."""
    if _state.model is None:
        raise HTTPException(status_code=503, detail="Model not loaded.")

    text = request.text.strip()
    if not text:
        raise HTTPException(status_code=422, detail="'text' must not be empty.")

    tokens = _state.tokenizer([text]).to(DEVICE)
    # Validate token length (CLIP max context is 77 tokens)
    token_count = (tokens != 0).sum().item()
    if token_count > 77:
        raise HTTPException(
            status_code=422,
            detail=f"Input too long: {token_count} tokens (max 77).",
        )
    with torch.no_grad():
        features = _state.model.encode_text(tokens)

    embedding = _normalize(features)
    return EmbeddingResponse(embedding=embedding, model=MODEL_NAME, dim=len(embedding))


@app.post("/embed/image", response_model=EmbeddingResponse)
async def embed_image(file: UploadFile = File(...)) -> EmbeddingResponse:
    """Return a normalized CLIP image embedding for an uploaded image file.

    Accepts any PIL-readable format (PNG, JPG, WEBP, etc.).
    """
    if _state.model is None:
        raise HTTPException(status_code=503, detail="Model not loaded.")

    content_type = file.content_type or ""
    if not content_type.startswith("image/"):
        raise HTTPException(status_code=422, detail=f"Unsupported content type: {content_type!r}. Expected an image.")

    raw = await file.read()
    # Enforce a 20 MB file size limit to prevent OOM
    if len(raw) > 20 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Image file too large (max 20 MB).")
    try:
        pil_image = Image.open(io.BytesIO(raw)).convert("RGB")
    except Exception as exc:
        raise HTTPException(status_code=422, detail=f"Cannot decode image: {exc}") from exc

    tensor = _state.preprocess(pil_image).unsqueeze(0).to(DEVICE)
    with torch.no_grad():
        features = _state.model.encode_image(tensor)

    embedding = _normalize(features)
    return EmbeddingResponse(embedding=embedding, model=MODEL_NAME, dim=len(embedding))


@app.post("/embed/image/base64", response_model=EmbeddingResponse)
async def embed_image_base64(request: Base64ImageRequest) -> EmbeddingResponse:
    """Return a normalized CLIP image embedding from a base64-encoded image string."""
    if _state.model is None:
        raise HTTPException(status_code=503, detail="Model not loaded.")

    try:
        raw = base64.b64decode(request.image_base64)
    except Exception as exc:
        raise HTTPException(status_code=422, detail=f"Invalid base64 data: {exc}") from exc

    if len(raw) > 20 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Image data too large (max 20 MB).")

    try:
        pil_image = Image.open(io.BytesIO(raw)).convert("RGB")
    except Exception as exc:
        raise HTTPException(status_code=422, detail=f"Cannot decode image: {exc}") from exc

    tensor = _state.preprocess(pil_image).unsqueeze(0).to(DEVICE)
    with torch.no_grad():
        features = _state.model.encode_image(tensor)

    embedding = _normalize(features)
    return EmbeddingResponse(embedding=embedding, model=MODEL_NAME, dim=len(embedding))


# ---------------------------------------------------------------------------
# POST /search — vector similarity search via Milvus
# ---------------------------------------------------------------------------


@app.post("/search", response_model=SearchResponse)
async def search(request: SearchRequest) -> SearchResponse:
    """Search for similar assets using a text or image query.

    Computes a CLIP embedding for the query, then searches the Milvus
    vector database for nearest neighbours.
    """
    import logging

    logger = logging.getLogger(__name__)

    if _state.model is None:
        logger.error("Search request rejected: CLIP model not loaded")
        raise HTTPException(status_code=503, detail="Model not loaded.")
    if _state.milvus is None:
        logger.error("Search request rejected: Milvus client not connected")
        raise HTTPException(status_code=503, detail="Milvus not connected.")

    if not request.text and not request.image_base64:
        raise HTTPException(
            status_code=422,
            detail="Either 'text' or 'image_base64' must be provided.",
        )

    # Compute query embedding
    if request.text:
        text = request.text.strip()
        if not text:
            raise HTTPException(status_code=422, detail="'text' must not be empty.")
        tokens = _state.tokenizer([text]).to(DEVICE)
        with torch.no_grad():
            features = _state.model.encode_text(tokens)
    else:
        try:
            raw = base64.b64decode(request.image_base64)
        except Exception as exc:
            logger.error("Invalid base64 in search request: %s", exc)
            raise HTTPException(status_code=422, detail=f"Invalid base64 data: {exc}") from exc
        try:
            pil_image = Image.open(io.BytesIO(raw)).convert("RGB")
        except Exception as exc:
            logger.error("Cannot decode search image: %s", exc)
            raise HTTPException(status_code=422, detail=f"Cannot decode image: {exc}") from exc
        tensor = _state.preprocess(pil_image).unsqueeze(0).to(DEVICE)
        with torch.no_grad():
            features = _state.model.encode_image(tensor)

    query_vector = _normalize(features)

    try:
        raw_results = _state.milvus.search(
            collection_name=request.collection,
            data=[query_vector],
            limit=request.limit,
            offset=request.offset,
            filter=request.filter_expr or "",
            output_fields=["name", "type"],
        )
    except Exception as exc:
        logger.error("Milvus search failed: %s", exc)
        raise HTTPException(status_code=502, detail=f"Search backend error: {exc}") from exc

    results = []
    for hit in raw_results[0]:
        results.append(SearchResult(
            id=str(hit["id"]),
            score=hit["distance"],
            metadata=hit.get("entity", {}),
        ))

    return SearchResponse(results=results, total=len(results))
