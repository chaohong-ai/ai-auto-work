# 05-素材库与语义检索 技术规格

## 1. 概述

构建预生成素材底库 + 语义检索系统。Phase 0 重点是：批量预生成素材入库、CLIP embedding 向量化、Milvus 向量检索 + MongoDB 标签检索双轨融合。实时生成服务在 Phase 0 仅做最小集成（底库未命中时降级提示）。

**范围**：
- 素材元数据 MongoDB 数据模型
- CLIP embedding 计算与 Milvus 入库
- 双轨检索（向量 + 标签）融合排序
- 批量预生成脚本（Tripo 3D / SDXL 2D / ElevenLabs 音效）
- 素材上传到腾讯云 COS
- search_asset / apply_asset MCP 工具的后端实现

**不做**：
- 实时生成服务完整链路（Phase 1）
- ComfyUI 自托管（Phase 2）
- 素材商店（Phase 2）

## 2. 文件清单

```
Backend/
├── internal/
│   ├── asset/
│   │   ├── model.go              # 素材 MongoDB 数据模型
│   │   ├── repository.go         # 素材 CRUD
│   │   ├── search.go             # 双轨检索逻辑
│   │   ├── embedding.go          # CLIP embedding 客户端
│   │   └── cos_storage.go        # 腾讯云 COS 上传/下载
│   └── milvus/
│       ├── client.go             # Milvus 客户端封装
│       └── collection.go         # Collection 定义与索引
│
Tools/
├── asset-pipeline/
│   ├── requirements.txt          # Python 依赖
│   ├── generate_3d.py            # Tripo API 批量 3D 生成
│   ├── generate_2d.py            # SDXL API 批量 2D 生成
│   ├── generate_audio.py         # ElevenLabs 批量音效生成
│   ├── compute_embeddings.py     # CLIP embedding 批量计算
│   ├── upload_to_cos.py          # 批量上传到 COS
│   ├── import_to_mongo.py        # 元数据导入 MongoDB
│   ├── import_to_milvus.py       # 向量导入 Milvus
│   ├── quality_check.py          # 质量检查（CLIP score）
│   └── asset_manifest.csv        # 素材清单定义
```

## 3. 数据模型

### 3.1 MongoDB 素材元数据

```go
// Backend/internal/asset/model.go

type Asset struct {
    ID          primitive.ObjectID `bson:"_id,omitempty" json:"id"`
    Name        string             `bson:"name" json:"name"`
    Description string             `bson:"description" json:"description"`
    Type        AssetType          `bson:"type" json:"type"`           // "3d_model", "2d_sprite", "texture", "audio_sfx", "audio_bgm"
    Category    string             `bson:"category" json:"category"`   // "character", "prop", "environment", ...
    Subcategory string             `bson:"subcategory" json:"subcategory"`
    Tags        []string           `bson:"tags" json:"tags"`

    // 存储信息
    FileURL     string             `bson:"file_url" json:"file_url"`     // COS URL
    FileSize    int64              `bson:"file_size" json:"file_size"`
    FileFormat  string             `bson:"file_format" json:"file_format"` // "glb", "png", "ogg"
    ThumbnailURL string            `bson:"thumbnail_url" json:"thumbnail_url"`

    // 素材属性
    Width       int                `bson:"width,omitempty" json:"width,omitempty"`
    Height      int                `bson:"height,omitempty" json:"height,omitempty"`
    Duration    float64            `bson:"duration,omitempty" json:"duration,omitempty"` // 音频时长
    VertexCount int                `bson:"vertex_count,omitempty" json:"vertex_count,omitempty"` // 3D 顶点数
    HasPBR      bool               `bson:"has_pbr,omitempty" json:"has_pbr,omitempty"`
    IsLoopable  bool               `bson:"is_loopable,omitempty" json:"is_loopable,omitempty"` // 音频循环

    // 风格
    Style       string             `bson:"style" json:"style"`           // "cartoon_lowpoly", "pixel_2d", "stylized_3d"
    StyleSeed   string             `bson:"style_seed,omitempty" json:"style_seed,omitempty"`

    // 质量
    CLIPScore   float32            `bson:"clip_score" json:"clip_score"` // CLIP 文图相似度
    QualityTier string             `bson:"quality_tier" json:"quality_tier"` // "high", "medium", "low"
    IsReviewed  bool               `bson:"is_reviewed" json:"is_reviewed"`

    // 生成信息
    Source      string             `bson:"source" json:"source"`         // "tripo", "sdxl", "dalle3", "elevenlabs", "manual"
    Prompt      string             `bson:"prompt,omitempty" json:"prompt,omitempty"`

    // 向量 ID（Milvus 中的对应 ID）
    MilvusID    int64              `bson:"milvus_id" json:"milvus_id"`

    CreatedAt   time.Time          `bson:"created_at" json:"created_at"`
}

type AssetType string

const (
    AssetType3DModel  AssetType = "3d_model"
    AssetType2DSprite AssetType = "2d_sprite"
    AssetTypeTexture  AssetType = "texture"
    AssetTypeSFX      AssetType = "audio_sfx"
    AssetTypeBGM      AssetType = "audio_bgm"
)
```

### 3.2 MongoDB 索引

```javascript
// assets collection
db.assets.createIndex({ "type": 1, "category": 1, "subcategory": 1 })
db.assets.createIndex({ "tags": 1 })
db.assets.createIndex({ "style": 1 })
db.assets.createIndex({ "quality_tier": 1, "clip_score": -1 })
db.assets.createIndex({ "name": "text", "description": "text", "tags": "text" })
```

### 3.3 Milvus Collection

```go
// Backend/internal/milvus/collection.go

const (
    CollectionName = "asset_embeddings"
    VectorDim      = 768  // CLIP ViT-L/14
)

// Schema:
//   - id:         int64 (primary key, auto-id)
//   - mongo_id:   varchar(24) (MongoDB ObjectID hex)
//   - asset_type: varchar(20)
//   - embedding:  float_vector(768)
//
// Index: HNSW, metric=COSINE, M=16, efConstruction=256
```

## 4. 双轨检索流程

```
search_asset(query="wooden treasure chest", type="3d_model", style="cartoon_lowpoly", limit=5)
    │
    ├──[路径1: 向量检索]
    │   1. CLIP text encoder: "wooden treasure chest" → embedding (768d)
    │   2. Milvus ANN search: Top-50, filter: asset_type="3d_model"
    │   3. 返回 [(mongo_id, similarity_score), ...]
    │
    ├──[路径2: 标签检索]
    │   1. MongoDB text search: "wooden treasure chest"
    │   2. Filter: type="3d_model", style="cartoon_lowpoly"
    │   3. 返回 [mongo_id, ...]
    │
    └──[融合排序]
        1. 向量结果: score = cosine_similarity (0~1)
        2. 标签结果: score = text_search_score (normalized)
        3. 融合: final_score = 0.7 * vector_score + 0.3 * tag_score
        4. 去重 + 排序 → Top-5
        5. 补充 MongoDB 完整信息 → 返回

命中判定：
  - final_score ≥ 0.75 → 返回底库素材
  - final_score < 0.75 → 返回 "no_match"，提示 AI 使用 generate_asset()
```

### 4.1 Go 检索实现

```go
// Backend/internal/asset/search.go

type SearchRequest struct {
    Query    string    `json:"query"`
    Type     AssetType `json:"type,omitempty"`
    Style    string    `json:"style,omitempty"`
    Limit    int       `json:"limit"`
}

type SearchResult struct {
    Assets     []Asset   `json:"assets"`
    HasMatch   bool      `json:"has_match"`     // final_score ≥ 0.75 的结果是否存在
    TopScore   float32   `json:"top_score"`
}

func (s *SearchService) Search(ctx context.Context, req SearchRequest) (*SearchResult, error) {
    // 1. 计算 embedding
    embedding, err := s.clipClient.TextEmbed(ctx, req.Query)

    // 2. Milvus 向量检索
    vectorResults, err := s.milvusClient.Search(ctx, embedding, req.Type, 50)

    // 3. MongoDB 标签检索
    tagResults, err := s.repo.TextSearch(ctx, req.Query, req.Type, req.Style, 50)

    // 4. 融合排序
    merged := mergeResults(vectorResults, tagResults, 0.7, 0.3)

    // 5. 截取 Top-N
    top := merged[:min(req.Limit, len(merged))]

    return &SearchResult{
        Assets:   top,
        HasMatch: len(top) > 0 && top[0].FinalScore >= 0.75,
        TopScore: top[0].FinalScore,
    }, nil
}
```

## 5. CLIP Embedding 服务

Phase 0 使用外部 CLIP API（避免自建 GPU 推理）：

```go
// Backend/internal/asset/embedding.go

type CLIPClient struct {
    // 方案 A: 调用 HuggingFace Inference API
    // 方案 B: 调用自建 FastAPI 服务 (CPU 推理，较慢但免费)
    baseURL string
    apiKey  string
}

func (c *CLIPClient) TextEmbed(ctx context.Context, text string) ([]float32, error) {
    // POST /embed/text { "text": "wooden crate" }
    // Response: { "embedding": [0.1, 0.2, ...] }  // 768d
}

func (c *CLIPClient) ImageEmbed(ctx context.Context, imageURL string) ([]float32, error) {
    // POST /embed/image { "url": "https://..." }
}
```

**Phase 0 推荐方案**：用 Python FastAPI 包装 `open_clip` 模型，CPU 推理（~1s/条），足够批量导入和检索使用。

```
Tools/clip-service/
├── requirements.txt     # open-clip-torch, fastapi, uvicorn
├── main.py              # FastAPI 服务
└── Dockerfile           # 容器化
```

## 6. 腾讯云 COS 存储

### 6.1 Bucket 结构

```
cos://gamemaker-assets-{region}/
├── 3d/
│   ├── {asset_id}.glb
│   └── {asset_id}_thumb.png
├── 2d/
│   ├── {asset_id}.png
│   └── {asset_id}_thumb.png
├── audio/
│   ├── sfx/{asset_id}.ogg
│   └── bgm/{asset_id}.ogg
└── generated/            # 用户实时生成的素材
    └── {user_id}/{asset_id}.{ext}
```

### 6.2 Go COS 客户端

```go
// Backend/internal/asset/cos_storage.go

type COSStorage struct {
    client *cos.Client
    bucket string
    cdnURL string  // CDN 加速域名
}

func (s *COSStorage) Upload(ctx context.Context, key string, data io.Reader) (string, error)
func (s *COSStorage) GetURL(key string) string  // 返回 CDN URL
func (s *COSStorage) Delete(ctx context.Context, key string) error
```

## 7. 批量生成脚本

### 7.1 素材清单格式 (asset_manifest.csv)

```csv
name,description,type,category,subcategory,tags,style,source,prompt
Wooden Crate,A simple wooden storage crate,3d_model,prop,container,"wooden,crate,container",cartoon_lowpoly,tripo,"low poly cartoon wooden crate, clean geometry, warm colors"
Green Slime,A bouncy green slime enemy,2d_sprite,character,enemy,"slime,enemy,green",cartoon_lowpoly,sdxl,"cartoon green slime character, transparent background, game sprite"
Coin Pickup,Golden coin sound effect,audio_sfx,sfx,pickup,"coin,pickup,reward",,elevenlabs,"coin pickup chime, 8-bit style, short"
```

### 7.2 生成流程

```bash
# 1. 批量生成素材文件
python Tools/asset-pipeline/generate_3d.py --manifest asset_manifest.csv --output ./temp/3d/
python Tools/asset-pipeline/generate_2d.py --manifest asset_manifest.csv --output ./temp/2d/
python Tools/asset-pipeline/generate_audio.py --manifest asset_manifest.csv --output ./temp/audio/

# 2. 质量检查
python Tools/asset-pipeline/quality_check.py --input ./temp/ --threshold 0.7

# 3. 上传到 COS
python Tools/asset-pipeline/upload_to_cos.py --input ./temp/ --bucket gamemaker-assets

# 4. 计算 CLIP embedding
python Tools/asset-pipeline/compute_embeddings.py --input ./temp/ --output ./temp/embeddings.npy

# 5. 导入数据库
python Tools/asset-pipeline/import_to_mongo.py --manifest asset_manifest.csv --cos-urls ./temp/cos_urls.json
python Tools/asset-pipeline/import_to_milvus.py --embeddings ./temp/embeddings.npy --mongo-ids ./temp/mongo_ids.json
```

## 8. Phase 0 素材目标

| 素材类型 | 数量 | 生成方式 | 预估成本 |
|----------|------|----------|----------|
| 3D 模型 (cartoon_lowpoly) | 500 | Tripo API | $75 |
| 2D 精灵 (cartoon) | 1000 | SDXL API / DALL-E 3 | $20 |
| 音效 | 200 | ElevenLabs | $6 |
| BGM | 20 | Suno | $1 |
| **合计** | **1720** | | **~$100** |

## 9. 验收标准

1. **MongoDB 数据模型**：assets collection 创建成功，索引正常
2. **Milvus Collection**：asset_embeddings 创建成功，HNSW 索引构建完成
3. **批量导入**：1720 条素材元数据导入 MongoDB，1720 条向量导入 Milvus
4. **COS 上传**：所有素材文件上传到腾讯云 COS，URL 可访问
5. **向量检索**：search("wooden crate", type="3d_model") 返回相关结果，耗时 < 100ms
6. **标签检索**：MongoDB text search 返回相关结果
7. **双轨融合**：融合排序结果质量优于单一路径
8. **CLIP 服务**：text embedding 和 image embedding 正常工作
9. **MCP 集成**：search_asset 工具通过 MCP HTTP API 可调用，返回素材列表含 COS URL
10. **apply_asset**：将搜到的素材应用到 Godot 节点（Sprite2D 设置 texture / AudioStreamPlayer 设置 stream）
