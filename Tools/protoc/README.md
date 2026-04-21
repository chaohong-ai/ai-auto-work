# protoc 工具链

本目录存放 Protocol Buffers 编译器二进制和 Go 代码生成插件，支持 Windows / Linux / macOS 三平台。

---

## 版本要求

| 工具 | 最低版本 | 说明 |
|------|----------|------|
| `protoc` | ≥ v27.0 | 支持 proto3 optional |
| `protoc-gen-go` | ≥ v1.34.0 | 与 `google.golang.org/protobuf` v1.34+ 兼容 |
| `protoc-gen-gdscript` | — | 内置 Python 脚本，位于 `Tools/protoc/gen-gdscript/protoc-gen-gdscript` |

---

## 目录结构

```
Tools/protoc/
├── bin/
│   ├── windows/
│   │   ├── protoc.exe           # Windows protoc 编译器
│   │   └── protoc-gen-go.exe    # Windows Go 代码生成插件
│   ├── linux/
│   │   ├── protoc               # Linux protoc 编译器
│   │   └── protoc-gen-go        # Linux Go 代码生成插件
│   └── mac/
│       ├── protoc               # macOS protoc 编译器
│       └── protoc-gen-go        # macOS Go 代码生成插件
└── gen-gdscript/
    └── protoc-gen-gdscript      # Python 脚本，生成 GDScript _pb.gd 文件
```

> **注意**: 二进制文件体积较大，不纳入 git 追踪（已在 .gitignore 中排除）。  
> 请按下方说明手动下载。

---

## 下载说明

### protoc

从 [github.com/protocolbuffers/protobuf/releases](https://github.com/protocolbuffers/protobuf/releases) 下载对应平台的 `protoc-<version>-<os>-<arch>.zip`，解压后将 `bin/protoc`（或 `bin/protoc.exe`）放入对应平台目录。

### protoc-gen-go

参考文档：[pkg.go.dev/google.golang.org/protobuf/cmd/protoc-gen-go](https://pkg.go.dev/google.golang.org/protobuf/cmd/protoc-gen-go)

```bash
# 安装到 $GOPATH/bin
go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.36.5

# 复制二进制到工具链目录
# Windows:  cp $GOPATH/bin/protoc-gen-go.exe Tools/protoc/bin/windows/
# Linux:    cp $GOPATH/bin/protoc-gen-go    Tools/protoc/bin/linux/
# macOS:    cp $GOPATH/bin/protoc-gen-go    Tools/protoc/bin/mac/
```

### protoc-gen-gdscript

脚本已内置于仓库，无需额外下载：

```
Tools/protoc/gen-gdscript/protoc-gen-gdscript
```

**Linux / macOS** 首次使用前需添加执行权限：

```bash
chmod +x Tools/protoc/gen-gdscript/protoc-gen-gdscript
```

**（可选）protoc plugin 模式**需要安装 `google-protobuf` Python 包：

```bash
pip install protobuf
```

若未安装，可直接使用独立模式（无需 protoc 二进制）：

```bash
python3 Tools/protoc/gen-gdscript/protoc-gen-gdscript \
    --proto_path=GameServer/proto \
    --gdscript_out=Engine/godot/project/proto/gen
```

---

## 使用方法

### Go 代码生成

```bash
cd GameServer
make proto-gen
```

输出目录：`GameServer/gen/proto/*.pb.go`

### GDScript 代码生成

**方式一：通过 Makefile（需要 protoc 二进制 + google-protobuf Python 包）**

```bash
cd GameServer
make proto-gen-gdscript
```

输出目录：`Engine/godot/project/proto/gen/*_pb.gd`

**方式二：独立模式（仅需 Python 3，无需 protoc）**

```bash
python3 Tools/protoc/gen-gdscript/protoc-gen-gdscript \
    --proto_path=GameServer/proto \
    --gdscript_out=Engine/godot/project/proto/gen
```

**支持的字段类型**：`string` `int32` `int64` `uint64` `bool` `bytes`

生成产物为纯 GDScript（Godot 4），不依赖 GDExtension。

---

## 当前已下载的工具

| 平台 | protoc | protoc-gen-go | 状态 |
|------|--------|---------------|------|
| Windows | — | — | 待下载 |
| Linux | — | — | 待下载 |
| macOS | — | — | 待下载 |

> `make proto-gen` 支持通过环境变量 `PROTOC` 覆盖工具路径：  
> `make proto-gen PROTOC=/path/to/protoc`  
> 若本机已安装 `protoc` 并在 `$PATH` 中，无需下载即可直接使用。
