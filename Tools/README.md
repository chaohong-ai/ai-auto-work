# Tools - 开发工具脚本

GameMaker 项目的可复用开发脚本集合，覆盖环境初始化、编译、测试、基础设施管理和素材流水线。

## 环境切换（测试 / 生产）

通过 `Server/configs/config.yaml` 中的 `env` 字段控制：

```yaml
env: test        # 测试环境：文件存本地，Docker 跑本地
env: production  # 生产环境：文件传 COS，Docker 远程管理
```

| 功能 | 测试环境 (`env: test`) | 生产环境 (`env: production`) |
|------|----------------------|---------------------------|
| 文件存储 | 本地磁盘 (`storage.local_path`) | 腾讯云 COS |
| 静态文件访问 | `http://localhost:8080/static/...` | CDN URL |
| Docker | 本地 Docker daemon | 远程 Docker host |
| 基础设施 | `docker-compose.yml` 一键启动 | 独立部署 |
| 素材上传 | `--local` 保存到本地目录 | 上传到 COS |

测试环境的本地存储路径在配置中指定：

```yaml
storage:
  local_path: "./data/storage"  # 所有文件存储到此目录
```

---

## 目录结构

| 子目录 | 用途 |
|--------|------|
| `ops/` | DevOps 脚本（环境初始化、编译、测试、基础设施、开发服务器、清理） |
| `utils/` | 通用工具脚本（如 `web_fetch.py`） |
| `asset-pipeline/` | 素材流水线脚本与编排 |
| `clip-service/` | CLIP 向量化服务 |
| `protoc/` | Protobuf 代码生成 |
| `templates/` | 测试模板 |

## 脚本一览

| 脚本 | 用途 |
|------|------|
| `ops/setup.sh` | 一键安装全部依赖 + 生成配置文件 |
| `ops/build-all.sh` | 编译全部模块 |
| `ops/test-all.sh` | 运行全部测试 |
| `ops/lint-all.sh` | 全模块代码检查 |
| `ops/docker-compose.yml` | 基础设施服务定义（含 Godot Headless） |
| `ops/start-infra.sh` | 启动基础设施（含健康检查） |
| `ops/stop-infra.sh` | 停止基础设施 |
| `ops/dev.sh` | 启动开发服务器 |
| `ops/clean.sh` | 清理构建产物 |
| `ops/e2e-test.sh` | 端到端集成测试 |
| `utils/web_fetch.py` | 网页抓取（WebFetch 不可用时的兜底） |
| `asset-pipeline/orchestrate.sh` | 素材流水线编排 |

---

## 环境初始化

### setup.sh

首次克隆项目后运行，安装所有模块依赖并生成配置文件。

```bash
bash Tools/ops/setup.sh
```

执行内容：
1. `Server/` — `go mod tidy`
2. `Engine/` — `go mod tidy`
3. `MCP/` — `npm install`
4. `Client/` — `npm install`
5. `Tools/clip-service/` — `pip install -r requirements.txt`
6. 从 `.example` 文件生成 `config.yaml`、`.env`、`.env.local`（仅当目标文件不存在时）

---

## 编译与检查

### build-all.sh

编译全部 4 个模块，任一失败则退出码非零。

```bash
bash Tools/ops/build-all.sh
```

| 模块 | 检查方式 |
|------|---------|
| Server (Go) | `go build ./...` |
| Engine (Go) | `go build ./...` |
| MCP (TypeScript) | `tsc --noEmit` |
| Client (Next.js) | `tsc --noEmit` |

### test-all.sh

运行全部模块的测试套件。

```bash
bash Tools/ops/test-all.sh
```

| 模块 | 测试框架 |
|------|---------|
| Server | `go test ./...` |
| MCP | Jest |
| Client | TypeScript 类型检查 |

### lint-all.sh

格式化和静态分析检查。

```bash
bash Tools/ops/lint-all.sh
```

| 模块 | 工具 |
|------|------|
| Server | `go vet` + `gofmt` |
| Engine | `go vet` + `gofmt` |
| MCP | ESLint |
| Client | Next.js lint |

---

## 基础设施

### docker-compose.yml

测试环境一键启动所有依赖服务（全部跑在本地 Docker）：

| 服务 | 端口 | 用途 |
|------|------|------|
| MongoDB 7.0 | 27017 | 用户/游戏/素材元数据 |
| Redis 7 | 6379 | 缓存 + 任务队列 |
| Milvus 2.4 | 19530 | 向量搜索（CLIP embeddings） |
| MinIO | 9001 (console) | Milvus 对象存储后端 |
| etcd | — | Milvus 元数据后端 |
| Godot Headless | 6007 | 游戏引擎容器（TCP/JSON-RPC） |

所有服务在同一 `gamemaker-net` 网络中，配置了 healthcheck 和持久化 volume。

### start-infra.sh

启动基础设施并等待所有服务就绪。

```bash
bash Tools/ops/start-infra.sh
```

脚本会轮询 MongoDB、Redis、Milvus、Godot 的健康检查接口，全部就绪后输出连接地址。

### stop-infra.sh

停止并移除所有基础设施容器（数据保留在 volume 中）。

```bash
bash Tools/ops/stop-infra.sh
```

---

## 开发服务器

### dev.sh

并行启动开发服务器，Ctrl+C 统一停止。

```bash
# 启动全部服务
bash Tools/ops/dev.sh

# 只启动指定服务
bash Tools/ops/dev.sh server   # Go 后端 :8080
bash Tools/ops/dev.sh mcp      # MCP Server
bash Tools/ops/dev.sh client   # Next.js :3000
bash Tools/ops/dev.sh clip     # CLIP 服务 :8100
```

| 参数 | 服务 | 端口 |
|------|------|------|
| `server` | Go 后端 API | 8080 |
| `mcp` | MCP TypeScript 服务 | 3100 |
| `client` | Next.js 前端 | 3000 |
| `clip` | CLIP embedding 服务 | 8100 |
| `all`（默认） | 以上全部 | — |

---

## 清理

### clean.sh

清理构建产物和依赖缓存。

```bash
# 常规清理（node_modules、dist、.next、data）
bash Tools/ops/clean.sh

# 深度清理（额外清除 Go build cache）
bash Tools/ops/clean.sh --deep
```

清理完成后运行 `bash Tools/ops/setup.sh` 重新安装依赖。

---

## 素材流水线

### asset-pipeline/orchestrate.sh

按顺序执行素材批量处理的 8 个步骤。

```bash
# 测试环境：保存到本地目录
bash Tools/asset-pipeline/orchestrate.sh --local

# 生产环境：上传到 COS
bash Tools/asset-pipeline/orchestrate.sh

# 指定 manifest 文件
bash Tools/asset-pipeline/orchestrate.sh --local path/to/manifest.csv
```

执行顺序：

| 步骤 | 脚本 | 说明 |
|------|------|------|
| 1 | `generate_2d.py` | SDXL 批量生成 2D 精灵 |
| 2 | `generate_3d.py` | Tripo 生成 3D 模型 |
| 3 | `generate_audio.py` | ElevenLabs 生成音频 |
| 4 | `quality_check.py` | 素材质量校验 |
| 5 | `compute_embeddings.py` | CLIP 向量化 |
| 6 | `upload_to_cos.py` | 测试：`--local` 存本地；生产：上传 COS |
| 7 | `import_to_mongo.py` | 元数据导入 MongoDB |
| 8 | `import_to_milvus.py` | 向量导入 Milvus |

任一步骤失败会中断后续流程。Manifest CSV 格式参见 `asset-pipeline/asset_manifest.csv`。

---

## 典型工作流

### 测试环境（本地开发）

```bash
# 1. 首次设置
bash Tools/ops/setup.sh

# 2. 启动基础设施（全部本地 Docker）
bash Tools/ops/start-infra.sh

# 3. 启动开发服务器
bash Tools/ops/dev.sh

# 4. 编码...

# 5. 编译检查
bash Tools/ops/build-all.sh

# 6. 运行测试
bash Tools/ops/test-all.sh

# 7. 素材处理（本地模式）
bash Tools/asset-pipeline/orchestrate.sh --local

# 8. 收工
bash Tools/ops/stop-infra.sh
```

### 生产环境

```bash
# 修改配置
# config.yaml: env: production + 填写 COS 凭证

# 素材处理（上传 COS）
bash Tools/asset-pipeline/orchestrate.sh
```
