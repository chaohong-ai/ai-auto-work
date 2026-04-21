# 数据层 — 存储选型与设计

---

## 1. MongoDB — 业务数据

| 维度 | 说明 |
|------|------|
| 选型理由 | 文档模型天然适配游戏/会话等嵌套结构；Schema 灵活，迭代期频繁变更字段无需 Migration；Go 官方驱动成熟 |
| 不选 PostgreSQL | 游戏数据结构多变（不同模板字段不同），关系型 Schema 约束反而是负担 |
| 版本 | 7.0 — 支持 Change Streams（实时监听）、事务 |

### 核心数据模型

```
Game {
  id, user_id, prompt, title, description,
  template, status (draft→queued→generating→ready→failed),
  task_id, session_id, screenshots[], timestamps
}

Session {
  id, user_id, game_id, container_id, mcp_session_id,
  phase (brainstorming | building),
  status (active | suspended | completed),
  rounds[], history[]
}

Task {
  id, game_id, status, prompt, template,
  current_phase, steps[], heal_attempts, error
}
```

---

## 2. Redis — 缓存/队列/会话

| 维度 | 说明 |
|------|------|
| 选型理由 | 一个组件同时覆盖缓存（热数据）、任务队列（Redis Streams）、会话状态（Session TTL），减少基础设施复杂度 |
| 不选 RabbitMQ/Kafka | 任务量级不大（非百万级），Redis Streams 足够，无需引入额外消息中间件 |
| 版本 | 7.x — Streams 消费组 + ACK + 死信队列原生支持 |

---

## 3. Milvus — 向量检索

| 维度 | 说明 |
|------|------|
| 选型理由 | 专业向量数据库，支持 HNSW/IVF 索引；CLIP 768 维嵌入高效检索；自部署成本可控 |
| 不选 Pinecone/Weaviate | Pinecone 托管费用高；Weaviate 功能过重；Milvus 开源免费 + 腾讯云有托管版 |
| 依赖 | etcd（元数据）+ MinIO（持久化） |

---

## 4. 文件存储 — COS / Local

| 维度 | 说明 |
|------|------|
| 生产 | **腾讯云 COS** — 国内访问快、与腾讯云生态集成、CDN 加速 |
| 开发 | **本地文件系统** — 零依赖、即开即用 |
| 接口抽象 | `storage.Storage` 统一接口，开发/生产通过配置切换，业务代码无感知 |

### 文件存储结构

```
文件存储/
├── users/{user_id}/
│   └── games/{game_id}/
│       ├── project/             # Godot 项目文件
│       ├── snapshots/           # 会话快照
│       ├── exports/             # 导出产物
│       └── assets/              # 游戏素材
└── sessions/{session_id}/
    ├── workspace/               # 工作区文件
    └── history/                 # AI 对话历史
```
