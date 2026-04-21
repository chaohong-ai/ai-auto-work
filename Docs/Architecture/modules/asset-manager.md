# Asset Manager Module

## Overview

Asset Manager provides the foundational data infrastructure for GameMaker: auto-increment ID generation, user type classification, game ID rules, and file system path calculation. All changes are within the Backend module.

## Core Components

### Counter Service (`internal/counter/`)
- **Repository interface**: `NextVal(ctx, name) (int64, error)` — atomic sequence generation
- **MongoCounterRepo**: Uses `FindOneAndUpdate` + `$inc` + upsert on `counters` collection
- **FakeCounterRepo** (`internal/testutil/fake_counter.go`): In-memory implementation for tests and mock mode

### User Model Extension (`internal/model/user.go`)
- `UID int64` — auto-increment user identifier, assigned at registration via counter service
- `Type string` — user category: `"u"` (personal), `"p"` (studio), `"s"` (system)
- Unique sparse index on `uid` field (allows backward compatibility with UID=0)

### Game ID (`internal/model/game.go`)
- `GameID string` — format `{user_type}_{uid}_{global_seq}` (e.g., `u_1001_1`)
- Generated in `GameHandler.Create` when counter + user repos are available
- Unique sparse index on `game_id` field
- Fallback: empty when running without counter service (CLI mode)

### Game Status Transitions (`internal/model/game.go`)
- Added `GameStatusPublished = "published"`
- `ValidStatusTransition(from, to)` enforces allowed transitions:
  - `draft → queued → generating → ready → published`
  - `ready → queued` (re-generate), `*generating/queued* → failed`, `failed → queued` (retry)

### Asset Path Service (`internal/assetpath/`)
- Pure calculation, zero IO dependencies
- `SystemAssetDir(assetType)` — e.g., `{root}/system_assets/image`
- `UserGameDir(uid, gameID)` — e.g., `{root}/user_game/1001/u_1001_1`
- `UserGameAssetDir(uid, gameID, assetType)` — subdirectory within game dir
- Path traversal protection: rejects `..`, `/`, `\` in segments

### Configuration (`internal/config/config.go`)
- `Asset.Root` — file system root for asset directories

## Key Files

| File | Purpose |
|------|---------|
| `internal/counter/repository.go` | Counter interface + Mongo implementation |
| `internal/counter/repository_test.go` | Counter unit tests (happy path + concurrency) |
| `internal/model/user.go` | User model with UID + Type fields |
| `internal/model/game.go` | Game model with GameID + AssetDir + status transitions |
| `internal/model/game_test.go` | Status transition validation tests |
| `internal/assetpath/service.go` | Path calculation service |
| `internal/assetpath/service_test.go` | Path calculation + traversal tests |
| `internal/handler/game.go` | GameID generation + AssetDir in Create handler |
| `internal/handler/game_handler_test.go` | Handler tests including GameID format validation |
| `internal/user/service.go` | UID allocation during registration |
| `internal/user/service_test.go` | UID assignment integration tests |
| `internal/testutil/fake_counter.go` | FakeCounterRepo for testing/mock mode |
| `internal/config/config.go` | Asset root configuration |
| `configs/config.yaml` | Default config values |

## Dependency Flow

```
counter.Repository ──► user.Service (UID allocation)
                   ──► handler.GameHandler (GameID generation)

user.UserRepository ──► handler.GameHandler (read user Type/UID for GameID)

assetpath.Service ──► handler.GameHandler (AssetDir calculation)

config.AssetConfig ──► assetpath.Service (root path)
```

## Design Decisions

1. **Counter as independent package** — not buried in model or repository; clean interface allows easy faking
2. **Optional dependencies** — counterRepo, userRepo, assetPath can be nil (backward compatible with CLI mode and older deployments)
3. **Dual Game model boundary respected** — all changes in `internal/model.Game` (REST chain), not `internal/game.Game` (session internal)
4. **No RBAC** — user Type is for identification and ID generation only, not authorization
