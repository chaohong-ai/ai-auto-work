# 宪法详细规则：Engine 与多平台

> **作用域：创作平台的 Engine/ 目录与导出链路。** 本文件是 `.ai/constitution.md` §6「多平台兼容」的详细展开，仅在涉及 Engine / 多平台导出时按需加载。
> **不适用于 `GameServer/`。**

## Linux 容器导出能力边界（不可协商）

Linux Godot 容器仅用于 Android / HTML5 / 资源导入与验证；完整 iOS 导出必须走 macOS + Xcode 流水线，不得在 Linux 容器方案里承诺"iOS 可导出"或把 iOS 验收挂到 Linux CI 步骤。涉及多平台验收的 feature，iOS 分支必须独立于 Linux 容器测试执行；缺 macOS runner 时明确标记为"未验收"而不是"通过"。详见 `.ai/context/project.md`"容器平台导出能力边界"。

---

> 以下规则从 endless-abyss 等 GDScript 游戏项目的多轮 develop-review 反复出现的代码质量问题中提取。

## project.godot 引擎版本元数据与工具链一致性（不可协商）

<!-- Context Repair: v0.0.4 test-thin-client task-01 H2 — project.godot config/features 与仓库 CI/export/dev 容器必须同为 4.6，避免 headless import/export 因版本不匹配静默失败 -->

任何对 `project.godot` 的 `config/features` / 引擎版本元数据的修改，必须满足以下条件之一，否则视为 **High**：

**条件 A — 保持基线一致**：修改后的 `config/features` 版本号（如 `"4.6"`）与以下文件中声明的 Godot 版本保持一致：
- `Scripts/docker-compose.dev.yml`（Godot 容器镜像标签）
- `Scripts/android-export.sh`（`GODOT_VERSION` 变量）
- `Scripts/pull-image.ps1`（镜像标签）
- `.github/workflows/` 中的 CI Godot 镜像引用

**条件 B — 同一 diff 全链路同步**：在**同一 PR / diff** 中同步更新所有以上文件到新版本，并在 develop-log / CI 证据中归档一次成功的 `godot --headless --import` 执行结果（exit code 0 + 无 ERROR 关键行）；若本机缺少 Godot 可执行文件，必须标注 `[ENVIRONMENT_MISSING: godot]` 并将相关 REQ 降级为 `PARTIAL_VERIFICATION`，不得标记 Pass。

**Reviewer 判定机制**：
- `project.godot` 变更且 `config/features` 版本号与仓库容器脚本版本不一致 → **High**（首次），RECURRING → **Critical**，计入宪法 §8 门禁计数
- 改了 `project.godot` 但未在同一 diff 同步容器脚本，或无 headless import 执行证据 → 同上
- `[ENVIRONMENT_MISSING: godot]` 仅豁免"headless 执行证据的 PARTIAL_VERIFICATION 降级"，不豁免"版本号不一致"本身的 High 判定

---

## GDScript 内部可变状态必须私有化（不可协商）

**内部可变状态**——Array、Dictionary、缓存句柄、运行时计数器等——必须使用 `_` 前缀标记为私有。外部访问通过 getter 方法，getter 返回 `.duplicate()` 副本而非可变引用。

**豁免**以下场景，不要求 `_` 前缀：
- `@export` 变量（有意暴露给 Inspector 的配置项）
- 对外公开的可调配置参数（如 `max_reconnect_attempts`、`move_speed`）
- 纯数据承载字段（Data Transfer Object / Config struct 的属性）
- `const` 常量

```gdscript
# ✅ 内部可变状态 → 私有化
var _zone_instances: Array = []
var _combo_count: int = 0
func get_zone_instances() -> Array:
    return _zone_instances.duplicate()

# ✅ 对外配置参数 → 公开合理
@export var max_reconnect_attempts: int = 5
var move_speed: float = 200.0

# ❌ 违宪：内部缓存/集合公开可变
var zone_instances: Array = []        # 内部集合暴露
var _hidden_types: Dictionary = {}    # 但 getter 返回原始引用
```

根因：endless-abyss 的 zone_speed / zone_stomp 中 `base_safe_weight` / `current_safe_weight` 内部权重被外部直接修改，review 多轮标记。

## GDScript 语义不自明的共享字面量必须抽常量（不可协商）

满足以下**任一条件**的数值字面量必须提取到 `config.json`、`config.gd` 或集中的 `CONST.gd`：
- **跨函数 / 跨文件重复出现**的同一数值
- **影响游戏平衡、协议行为、平台适配**的参数（分数倍率、帧率阈值、网络超时等）
- **语义不自明**——读到数字无法立刻理解"为什么是这个值"

**豁免**以下场景，允许保留字面量：
- 仅在当前函数内使用一次的布局偏移、动画时长、插值参数、碰撞阈值等本地值
- 数学常量（PI、TAU）、索引（0、1、-1）、位运算掩码
- Tween 的 duration/delay 等 Godot API 直接消费的一次性参数

```gdscript
# ❌ 语义不自明 + 影响平衡
var hp := 999                    # 999 表示"无敌"？抽常量
var layers := 20                 # 跨多处使用，抽到 Config

# ✅ 抽常量
const INVINCIBLE_HP := 999
var layers := Config.LAYERS_PER_ZONE

# ✅ 本地一次性值，保留合理
tween.tween_property(self, "modulate:a", 0.0, 0.3)  # 0.3s 淡出
position.x = clamp(position.x, 16.0, screen_width - 16.0)  # 边缘留白
```

根因：endless-abyss 中跨文件重复的平衡参数（层数、倍率、权重）散落在多个文件中，修改一处漏改另一处。

## GDScript 空值守卫（不可协商）

所有对外部对象 / 字典 / 节点的访问必须先做空值或存在性检查，带 `push_error` / `push_warning` 日志。禁止直接访问可能为 null 的属性——GDScript 不像静态语言有编译期保护，运行时 null access 直接崩溃。

```gdscript
# ✅ 正确
func show_stats(game_manager: GameManager) -> void:
    if game_manager == null:
        push_error("DeathScreen.show_stats: game_manager is null")
        return
    var player = game_manager.get_player()
    if player == null:
        push_warning("DeathScreen.show_stats: player is null, using defaults")
        _show_default_stats()
        return
    _show_player_stats(player)

# ❌ 违宪：直接访问可能为 null 的属性
func show_stats(game_manager) -> void:
    var score = game_manager.player.score  # 两层都可能 null
```

特别关注以下高危场景：
- 回调函数中访问 `_player`、`_game_manager` 等可能已被释放的引用
- `get_node()` 返回值直接使用（节点可能不存在或已释放）
- Dictionary 直接用 key 访问（key 可能不存在，应使用 `.get(key, default)` 或 `.has(key)` 判断）

根因：endless-abyss 的 death_screen.gd、zone_speed.gd、game_manager.gd 中 8+ 处 null/type safety 问题在 review 后才发现。

## GDScript 场景树生命周期：需要 _process 或 add_child 的类必须 extends Node（不可协商）

GDScript 类的继承选择对场景树参与权有决定性影响：

- **`extends Node`**：参与场景树，`_process`、`_physics_process` 由引擎每帧调用，`add_child()` 合法。
- **`extends RefCounted`**：不参与场景树，`_process` 永远不会被调用，`add_child()` 会在运行时抛出类型错误。

**规则**：
- 需要 `_process`、`_physics_process`、`_ready`、`_input`，或需要通过 `add_child` 加入场景树的类 → 必须 `extends Node`（或其子类如 Node2D/Node3D/Control）。
- 仅作数据载体、工具类、纯函数集合，**无任何场景树依赖**的辅助类 → 允许 `extends RefCounted`。

```gdscript
# ✅ 网络/IO 组件需要 _process 轮询 → extends Node
class_name TcpTransport extends Node

# ✅ 纯数据解码工具，无场景树依赖 → extends RefCounted 合理
class_name PacketCodec extends RefCounted

# ❌ 违宪：需要 _process 却继承 RefCounted，_process 永远不触发
class_name ITransport extends RefCounted
```

根因：v0.0.4 game-net plan 中 `ITransport extends RefCounted` 导致 C1 严重 bug：`add_child(_transport)` 运行时崩溃，`_process` 轮询永不执行。

---

## GDScript TCP 流解析必须使用 reassembly buffer（不可协商）

GDScript 的 `StreamPeerTCP.get_data(n)` 是**消耗性操作**——已读字节从 TCP 缓冲区永久移除，无法撤销或回退（没有 peek 操作）。TCP 是字节流，不保证消息边界。

**规则**：
- 每 `_process` 帧调用 `get_data(get_available_bytes())` 将所有可用字节**追加**到实例级 `PackedByteArray` 缓冲区。
- 仅在缓冲区积累了**完整帧**所需字节数后，才切帧处理。未消费字节保留在缓冲区。
- **禁止** 先读取 Len 字段、检查剩余字节不足后 `break`——Len 字段已被消耗，下次从 body 中间开始解析，导致帧边界永久错乱。

```gdscript
# ✅ 正确：reassembly buffer 模式
var _reassembly_buf: PackedByteArray

func _read_packets() -> void:
    var avail := _socket.get_available_bytes()
    if avail > 0:
        var result := _socket.get_data(avail)
        if result[0] == OK:
            _reassembly_buf.append_array(result[1])
    while _reassembly_buf.size() >= 4:
        var body_len := # 从 _reassembly_buf[0..3] 读取长度
        if _reassembly_buf.size() < 4 + body_len:
            break  # 等待完整帧，已有字节保留不丢失
        var frame := _reassembly_buf.slice(0, 4 + body_len)
        _reassembly_buf = _reassembly_buf.slice(4 + body_len)
        # 处理 frame ...

# ❌ 违宪：消耗 4B Len 后因数据不足 break，后续解析错乱
_recv_buf = _socket.get_data(4)[1]       # 4B 永久消耗
var body_len := # 从 _recv_buf 读取
if _socket.get_available_bytes() < body_len:
    break  # 下次从 body 中间开始，帧边界损坏
```

根因：v0.0.4 game-net plan 中 C2 bug——`_read_packets()` 消耗 4B Len 后对不完整 body `break`，导致连续帧解析全部错乱。

---

## GDScript 日志与调试 API 白名单（不可协商）

**背景**：Round 5 plan-review I-4 发现 `push_print()` 被写入 plan 模板，但该函数在 Godot 4 GDScript 中**不存在**，导致运行时错误污染日志并可能跳过后续初始化代码。

**允许使用**：

| 函数 | 用途 |
|------|------|
| `print(...)` | 普通调试输出 |
| `push_warning(msg)` | 非致命异常，记录到错误日志但不中断执行 |
| `push_error(msg)` | 严重错误，记录到错误日志（宪法空值守卫规则要求使用） |

**禁止使用**：

| 函数 | 原因 |
|------|------|
| `push_print()` | 不存在于 Godot 4 GDScript，调用直接抛运行时错误 |
| `printerr()` | 语义不明，与 `print` + stderr 重复；统一用 `push_error` |

**Plan / Develop Review 门禁**：代码或 plan 中出现非白名单日志函数，视为 **Important** 级问题，须修复后方可进入下一阶段。

---

## GDScript 函数参数类型注解（推荐）

所有公开方法和信号回调的参数必须带类型注解。内部辅助方法建议带类型注解。类型注解帮助 Godot 编辑器提供自动补全和静态分析提示，减少运行时类型错误。

```gdscript
# ✅ 正确
func apply_damage(target: Node2D, amount: float, source: StringName) -> void:
    pass

# ❌ 不推荐
func apply_damage(target, amount, source):
    pass
```

## GDScript HTTPClient HTTPS/TLS 连接（不可协商）

<!-- Context Repair: v0.0.4 thin-client task-05 M1 — SSEManager.gd strip https:// 后以 port 80 且无 TLS options 连接，部署到 HTTPS Backend 后 SSE 稳定失败 -->

在 GDScript 中使用 `HTTPClient.connect_to_host()` 发起网络连接时，必须根据 scheme 选择正确的端口和 TLS 选项：

- `https://` → 默认端口 `443`，第三参数传 `TLSOptions.client()`
- `http://`  → 默认端口 `80`，第三参数传 `null`（或省略）

**URL 解析必须在 strip scheme 之前提取 scheme**，再决定端口与 TLS 行为。

```gdscript
# ✅ 正确：先提取 scheme，再决定端口和 TLS
func _parse_url(base_url: String) -> void:
    _use_tls = base_url.begins_with("https://")
    var stripped = base_url.trim_prefix("https://").trim_prefix("http://")
    var parts = stripped.split(":")
    _host = parts[0]
    _port = int(parts[1]) if parts.size() > 1 else (443 if _use_tls else 80)

func _do_connect() -> void:
    var tls_opts = TLSOptions.client() if _use_tls else null
    _client.connect_to_host(_host, _port, tls_opts)

# ❌ 违宪：strip 后回落 port 80，HTTPS base URL 连到错误端口且无 TLS
var stripped = base_url.replace("https://", "")
_client.connect_to_host(stripped, 80)  # HTTPS → port 80, 无 TLS → 连接失败
```

同类场景：`WebSocketPeer` 使用 `wss://` 时 Godot 4 会自动处理 TLS，但 `HTTPClient` **不会**——必须手动传 `TLSOptions`。

## ThinClient SessionScene 双连接编排义务（不可协商）

<!-- Context Repair: v0.0.4 thin-client task-06 C1 RECURRING — init_session() 仅调用 SSEManager.connect_sse()，遗漏 SyncManager.connect_ws()，SubViewport scene_root 收不到 Headless Godot WS 推送，违反 project.md WS 端口合同 -->

`SessionScene.gd` 是 ThinClient 连接生命周期的编排者。`init_session()` 必须**同时**建立 SSE 和 WS 两条连接，任意一条缺失均视为合同断裂：

1. **读取 WS URL**：优先从参数 `session.get("sync_ws_url", "")` 读取；为空时回落 `fallback_ws_host`（`"ws://localhost:9001"`）
2. **WS 连接**：调用 `SyncManager.set_scene_root(<scene_root_node>)` + `SyncManager.connect_ws(_ws_url)`
3. **SSE 连接**：调用 `SSEManager.connect_sse(...)`
4. **退出清理**：`_exit_tree()` 必须同时断开两条连接（`SyncManager.disconnect_ws()` + SSE 等价断开）

```gdscript
# ✅ 正确：双连接编排
func init_session(session: Dictionary) -> void:
    _ws_url = session.get("sync_ws_url", fallback_ws_host)
    SyncManager.set_scene_root($SubViewport/scene_root)
    SyncManager.connect_ws(_ws_url)
    SSEManager.connect_sse(session.get("sse_url", ""))

func _exit_tree() -> void:
    SyncManager.disconnect_ws()
    SSEManager.disconnect_sse()

# ❌ 违宪：只连 SSE，WS 链路断裂
func init_session(session: Dictionary) -> void:
    SSEManager.connect_sse(...)   # SyncManager 未调用 → SubViewport 永远空白
```

**Reviewer 判定**：
- `init_session()` 缺少 `SyncManager.connect_ws()` 调用 → 直接 **Critical**（违反 project.md WS 端口合同，RECURRING → 无豁免）
- `_exit_tree()` 缺 WS/SSE 任一断开 → **High**（资源泄漏）
- 上述问题属"实现编排缺失"，独立于 `[ENVIRONMENT_MISSING: godot]`，不受 headless 环境豁免。

<!-- Context Repair: v0.0.4 thin-client task-07 C1 RECURRING — task-07 将 connect_ws 改名为 connect_sync，单方面覆盖 .ai/ 合同；原文无"命名固化"显式约束，执行者按 task 文件实现导致系统性回归 -->
**公开 API 命名固化（不可协商）**：`connect_ws(url)` / `disconnect_ws()` 是 SyncManager WS 连接的唯一权威公开 API 名。若需改名，必须在同一 diff 中同步更新以下三处，否则等同合同回归：
1. 本节示例代码
2. `.ai/context/project.md` Headless Godot / ThinClient WS 端口合同节
3. 所有受影响的 task / plan 验收文档

**Reviewer 判定**：task 代码使用非 `connect_ws` / `disconnect_ws` 名称而未同步更新上述三处 → 直接 **Critical（`[CONTRACT_OVERRIDE]`）**，无豁免。

<!-- Context Repair: v0.0.4 thin-client task-07 H3 — task-07 将 sync_failed / _max_reconnect / get_reconnect_count() 单方面改名，plan.md / acceptance-report.md 仍持有 connection_failed / max_reconnect_attempts / get_reconnect_attempts()，导致 UI 接线时失败信号静默丢失 -->
**重连公开合同（不可协商）**：以下 REQ-013 公开接口名与连接/断开 API 同等级别，task 文件不得单方面改名：

| 权威名（plan.md / acceptance-report.md）| 禁止改名为 |
|---|---|
| 失败信号 `connection_failed` | `sync_failed` 或其他 |
| 重连计数访问器 `get_reconnect_attempts()` | `get_reconnect_count()` 或其他 |
| 最大重连次数字段 `max_reconnect_attempts` | `_max_reconnect` 或其他私有名 |

改名必须在同一 diff 中同步更新本节、`project.md` WS 合同节、`plan.md`、`acceptance-report.md` 及所有消费者。未同步 → **Critical（`[CONTRACT_OVERRIDE]`）**，无豁免。

<!-- Context Repair: v0.0.4 thin-client task-08 M1 RECURRING — WS payload handlers assign pos/nodes/node_data as Array/Dictionary without is-type guards; malformed frames trigger GDScript runtime errors interrupting WS processing -->
## GDScript WS/网络消息 Payload 类型守卫（不可协商）

任何从外部来源（WebSocket、HTTP 响应、JSON.parse_string）读取的 `Variant` 值，在赋值给 typed 变量或调用方法前，**必须**先做 `is` 类型守卫；未通过守卫时调用 `push_warning` 并 `return`/`continue`。

```gdscript
# ✅ 正确：type guard 先行，格式错误帧仅产生 warning，不中断 WS 处理
func _handle_sync(data: Dictionary) -> void:
    if not data.has("nodes") or not data["nodes"] is Array:
        push_warning("SyncManager: sync frame missing/invalid nodes")
        return
    for node_data in (data["nodes"] as Array):
        if not node_data is Dictionary:
            push_warning("SyncManager: sync node_data is not Dictionary")
            continue
        _handle_update(node_data)

# ❌ 违宪：直接赋值 Variant，格式错误帧触发运行时 Error
var nodes: Array = data["nodes"]   # 若 data["nodes"] 为 int，立即崩溃
```

**适用场景**：`_handle_spawn`、`_handle_update`、`_handle_sync` 及所有解析 WebSocket / HTTP / JSON 消息的处理函数。

**Reviewer 判定**：payload handler 对 `Array`/`Dictionary` 类型字段无 `is` 类型守卫 → **Medium**（RECURRING → High，计入宪法 §8 门禁计数）。
