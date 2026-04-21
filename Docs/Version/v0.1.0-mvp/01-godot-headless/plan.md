# 01-Godot Headless 容器环境 技术规格

## 1. 概述

搭建 Godot 4.3 Headless 模式的 Docker 容器环境，支持 xvfb 软件渲染截图，作为整个 AI 游戏生成管线的引擎层基础。

**范围**：
- Docker 镜像构建（Godot Headless + xvfb + Mesa llvmpipe）
- 容器生命周期管理（创建/启动/停止/回收）
- 项目文件挂载与输出目录约定
- 截图管线（xvfb → PNG）
- 健康检查与超时回收

**不做**：
- Kubernetes / KEDA 编排（Phase 1）
- gVisor 沙箱（Phase 1）
- 多容器并发池（本模块仅单容器验证，07-backend-api 管理并发）

## 2. 文件清单

```
Engine/
├── docker/
│   ├── Dockerfile                  # Godot Headless 镜像
│   ├── .dockerignore
│   ├── entrypoint.sh               # 容器入口脚本
│   └── healthcheck.sh              # 容器健康检查
├── godot/
│   ├── project/                    # 基础 Godot 项目骨架
│   │   ├── project.godot           # 项目配置文件
│   │   ├── export_presets.cfg      # H5 导出预设
│   │   └── scripts/
│   │       ├── screenshot.gd       # 截图脚本
│   │       └── health_check.gd     # 引擎健康检查脚本
│   └── templates/                  # 导出模板存放目录
│       └── .gitkeep
└── scripts/
    ├── build-image.sh              # 镜像构建脚本
    ├── run-container.sh            # 本地运行/调试脚本
    └── test-headless.sh            # 集成测试脚本
```

## 3. Docker 镜像设计

### 3.1 Dockerfile

```dockerfile
FROM ubuntu:22.04

ARG GODOT_VERSION=4.3-stable
ARG GODOT_RELEASE_URL=https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}

# 系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget unzip ca-certificates \
    libfontconfig1 libgl1-mesa-glx libgl1-mesa-dri \
    xvfb libxcursor1 libxinerama1 libxrandr2 libxi6 \
    mesa-utils libasound2 libpulse0 \
    && rm -rf /var/lib/apt/lists/*

# 下载 Godot
RUN wget -q ${GODOT_RELEASE_URL}/Godot_v${GODOT_VERSION}_linux.x86_64.zip \
    && unzip Godot_v${GODOT_VERSION}_linux.x86_64.zip \
    && mv Godot_v${GODOT_VERSION}_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm Godot_v${GODOT_VERSION}_linux.x86_64.zip

# 下载 H5 导出模板
RUN mkdir -p /root/.local/share/godot/export_templates/${GODOT_VERSION} \
    && wget -q ${GODOT_RELEASE_URL}/Godot_v${GODOT_VERSION}_export_templates.tpz \
    && unzip Godot_v${GODOT_VERSION}_export_templates.tpz \
    && mv templates/* /root/.local/share/godot/export_templates/${GODOT_VERSION}/ \
    && rm -rf templates Godot_v${GODOT_VERSION}_export_templates.tpz

# 强制 CPU 软件渲染
ENV LIBGL_ALWAYS_SOFTWARE=1
ENV GALLIUM_DRIVER=llvmpipe
ENV DISPLAY=:99

# 工作目录
WORKDIR /project

# 输出目录
RUN mkdir -p /output

# 非 root 用户
RUN useradd -m -s /bin/bash godot
RUN chown -R godot:godot /project /output
USER godot

COPY entrypoint.sh /entrypoint.sh

HEALTHCHECK --interval=10s --timeout=5s --retries=3 \
    CMD /healthcheck.sh

ENTRYPOINT ["/entrypoint.sh"]
```

### 3.2 entrypoint.sh

```bash
#!/bin/bash
set -e

# 启动 xvfb
Xvfb :99 -screen 0 1280x720x24 -ac +extension GLX &
XVFB_PID=$!
sleep 1

# 根据 MODE 环境变量决定行为
case "${MODE:-idle}" in
  "import")
    # 导入项目资源（静态检查）
    godot --headless --import --path /project 2>&1
    ;;
  "run")
    # 运行游戏（用于验证）
    timeout ${TIMEOUT:-30} godot --rendering-driver opengl3 --path /project 2>&1 || true
    ;;
  "screenshot")
    # 运行截图脚本
    timeout ${TIMEOUT:-15} godot --rendering-driver opengl3 --headless \
      --path /project --script scripts/screenshot.gd 2>&1
    ;;
  "export")
    # H5 导出
    godot --headless --export-release "HTML5" /output/game.zip --path /project 2>&1
    ;;
  "idle")
    # 空闲等待（预热模式，等待外部 MCP 命令）
    echo "READY"
    godot --rendering-driver opengl3 --path /project --headless 2>&1 &
    GODOT_PID=$!
    # 等待信号
    trap "kill $GODOT_PID $XVFB_PID 2>/dev/null; exit 0" SIGTERM SIGINT
    wait $GODOT_PID
    ;;
  *)
    echo "Unknown MODE: ${MODE}"
    exit 1
    ;;
esac

# 清理
kill $XVFB_PID 2>/dev/null || true
```

### 3.3 截图脚本 (screenshot.gd)

```gdscript
extends SceneTree

func _init():
    # 加载目标场景
    var scene_path = OS.get_environment("SCENE_PATH")
    if scene_path == "":
        scene_path = "res://main.tscn"

    var scene_resource = load(scene_path)
    if scene_resource == null:
        printerr("Failed to load scene: " + scene_path)
        quit(1)
        return

    var scene = scene_resource.instantiate()
    root.add_child(scene)

    # 等待渲染完成（2帧）
    await process_frame
    await process_frame

    # 截图
    var img = root.get_viewport().get_texture().get_image()
    var output_path = OS.get_environment("OUTPUT_PATH")
    if output_path == "":
        output_path = "/output/screenshot.png"
    img.save_png(output_path)

    print("Screenshot saved: " + output_path)
    quit(0)
```

## 4. 容器接口约定

### 4.1 卷挂载

| 宿主机路径 | 容器路径 | 说明 |
|-----------|---------|------|
| `{work_dir}/project/` | `/project/` | Godot 项目文件（读写） |
| `{work_dir}/output/` | `/output/` | 输出目录（截图/导出包） |

### 4.2 环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `MODE` | `idle` | 容器运行模式：idle/import/run/screenshot/export |
| `TIMEOUT` | `30` | 操作超时秒数 |
| `SCENE_PATH` | `res://main.tscn` | 截图目标场景 |
| `OUTPUT_PATH` | `/output/screenshot.png` | 截图输出路径 |

### 4.3 容器退出码

| 退出码 | 含义 |
|--------|------|
| 0 | 成功 |
| 1 | Godot 运行时错误 |
| 124 | 超时（timeout 命令返回） |
| 137 | 被 OOM Killer 终止 |

## 5. Go 容器管理接口

### 5.1 接口定义

```go
// Engine/container/manager.go

package container

import (
    "context"
    "time"
)

// ContainerConfig 容器启动配置
type ContainerConfig struct {
    Mode       string        // idle, import, run, screenshot, export
    Timeout    time.Duration // 操作超时
    ProjectDir string        // 宿主机项目目录
    OutputDir  string        // 宿主机输出目录
    ScenePath  string        // 截图场景路径 (可选)
}

// ContainerStatus 容器状态
type ContainerStatus string

const (
    StatusCreating ContainerStatus = "creating"
    StatusReady    ContainerStatus = "ready"
    StatusBusy     ContainerStatus = "busy"
    StatusStopped  ContainerStatus = "stopped"
    StatusError    ContainerStatus = "error"
)

// ContainerInfo 容器信息
type ContainerInfo struct {
    ID        string
    Status    ContainerStatus
    CreatedAt time.Time
    ProjectID string // 关联的项目 ID（空表示空闲）
}

// Manager 容器管理器接口
type Manager interface {
    // Create 创建并启动一个 Godot 容器
    Create(ctx context.Context, cfg ContainerConfig) (*ContainerInfo, error)

    // Exec 在运行中的容器内执行命令
    Exec(ctx context.Context, containerID string, cmd []string) (stdout string, stderr string, exitCode int, err error)

    // CopyTo 将文件/目录复制到容器中
    CopyTo(ctx context.Context, containerID string, srcPath string, dstPath string) error

    // CopyFrom 从容器中复制文件/目录
    CopyFrom(ctx context.Context, containerID string, srcPath string, dstPath string) error

    // Stop 停止并移除容器
    Stop(ctx context.Context, containerID string) error

    // Status 查询容器状态
    Status(ctx context.Context, containerID string) (*ContainerInfo, error)

    // List 列出所有容器
    List(ctx context.Context) ([]*ContainerInfo, error)
}
```

### 5.2 Docker 实现

```go
// Engine/container/docker.go

package container

// DockerManager 基于 Docker SDK 的实现
// 使用 github.com/docker/docker/client
type DockerManager struct {
    cli       *client.Client
    imageName string // "gamemaker/godot-headless:4.3"
    network   string // Docker 网络名（MCP Server 需要与容器通信）
}
```

## 6. 资源限制

| 资源 | 限制 | 说明 |
|------|------|------|
| CPU | 1 core | 单容器不超过 1 核 |
| 内存 | 512 MB | Godot Headless 典型占用 200-400MB |
| 磁盘 | 1 GB tmpfs | 项目临时文件 |
| 网络 | 仅内部网络 | 禁止外网访问（安全） |
| 生命周期 | 10 分钟 | 超时自动回收 |

## 7. 验收标准

1. **镜像构建**：`docker build` 成功，镜像大小 < 2GB
2. **Headless 启动**：容器启动后 `godot --headless` 正常运行，无崩溃
3. **截图功能**：给定一个 .tscn 场景文件，容器能在 5 秒内输出 PNG 截图
4. **资源导入**：`MODE=import` 能完成 Godot 资源导入，检测场景完整性
5. **H5 导出**：`MODE=export` 能导出 H5 zip 包
6. **超时回收**：超时后容器自动停止，进程不残留
7. **Go 管理接口**：Manager 接口能创建/停止容器，执行命令，复制文件
8. **日志输出**：Godot 的 stdout/stderr 能被 Go 侧捕获
