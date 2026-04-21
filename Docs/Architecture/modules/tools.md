# Tools — Python 工具服务

> 端口：8100 (CLIP) | 目录：`Tools/` | 语言：Python

---

## 1. 选型理由

| 维度 | 选择 | 理由 | 不选 |
|------|------|------|------|
| 语言 | **Python 3.12+** | AI/ML 生态最强（OpenCLIP、PyTorch），素材处理库丰富（Pillow、pydub） | Go（无 CLIP/PyTorch 实现） |
| Web 框架 | **FastAPI** | 自动 OpenAPI 文档、Pydantic 校验、async 支持、性能优于 Flask | Flask（同步、无自动文档） |
| CLIP 模型 | **open-clip-torch** (ViT-L/14) | 开源免费、768 维嵌入、多语言支持、自部署无 API 成本 | OpenAI CLIP API（付费） |
| 向量库 | **pymilvus** | Milvus 官方 Python SDK | |

**为什么 CLIP 服务用 Python 而不用 Go？** OpenCLIP/PyTorch 生态只在 Python，Go 没有等效实现。CLIP 推理是 GPU 密集型任务，Python GIL 不是瓶颈。

---

## 2. 架构设计

```
Tools/
├── clip-service/                # CLIP 嵌入服务 (:8100)
│   ├── main.py                  #   FastAPI 入口
│   │                            #   POST /embed/image — 图片 → 768d 向量
│   │                            #   POST /embed/text  — 文本 → 768d 向量
│   │                            #   POST /search      — 语义搜索（调 Milvus）
│   ├── model.py                 #   OpenCLIP 模型加载与推理
│   ├── Dockerfile               #   CUDA 基础镜像 + PyTorch + OpenCLIP
│   └── tests/                   #   pytest 测试
│
└── asset-pipeline/              # 素材批处理管线
    ├── scripts/
    │   ├── ingest.py            #   批量导入：下载 → 处理 → 嵌入 → 入库
    │   ├── process.py           #   图片处理：缩放、裁剪、格式转换、透明背景
    │   └── index.py             #   索引构建：CLIP 嵌入 → Milvus 写入 + MongoDB 元数据
    └── tests/                   #   pytest 测试
```

---

## 3. 素材搜索流程

```
用户搜索 "像素风格的跳跃怪物"
      │
      ▼
  Backend ──▶ CLIP Service: POST /embed/text
                    │
                    ▼
              text → 768d 向量
                    │
                    ▼
              Milvus: ANN 搜索 (HNSW, top-K)
                    │
                    ▼
              返回匹配素材 ID + 相似度分数
                    │
                    ▼
  Backend ──▶ MongoDB: 查询素材元数据 (URL, 标签, 尺寸)
                    │
                    ▼
              返回给 Client 展示
```
