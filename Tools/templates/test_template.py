# ============================================================================
# Python FastAPI 接口测试模板
# ============================================================================
#
# 本模板展示如何为 FastAPI 应用编写 pytest 测试。
# 使用方式：复制本文件到目标服务的 tests/ 目录下，重命名为 test_xxx.py，
# 然后根据注释提示替换占位符。
#
# 项目约定：
#   - 使用 pytest 作为测试框架
#   - 使用 httpx.AsyncClient（ASGITransport）测试异步 FastAPI 端点
#   - fixture 定义在 conftest.py 中，测试文件直接引用
#   - mock 外部依赖（Milvus、MongoDB、COS），不 mock 内部模块
#   - 测试文件命名：test_*.py
#
# 依赖包：
#   - pytest, pytest-asyncio
#   - httpx（用于 AsyncClient + ASGITransport）
#   - unittest.mock（标准库，用于 MagicMock / patch）
#
# 参考实现：
#   - Tools/clip-service/tests/conftest.py   — fixture 示例
#   - Tools/clip-service/tests/test_health.py — 异步测试示例
#   - Tools/asset-pipeline/tests/conftest.py  — fixture 示例
# ============================================================================

from unittest.mock import MagicMock, patch

import pytest

# ============================================================================
# 1. pytest fixture — 测试客户端
# ============================================================================
# fixture 通常定义在 conftest.py 中，此处展示完整写法供参考。
# 如果你的 conftest.py 已有 test_client fixture，直接在测试函数参数中引用即可。
#
# 【替换】将 "your_app.main" 改为你的 FastAPI app 所在模块。


@pytest.fixture
def test_client():
    """创建绑定到 FastAPI app 的异步测试客户端。

    使用 httpx.AsyncClient + ASGITransport，支持测试异步端点。
    yield 模式确保测试结束后自动清理资源。
    """
    from httpx import ASGITransport, AsyncClient

    # 【替换】导入你的 FastAPI app 实例
    # from your_app.main import app
    #
    # 【可选】注入 mock 依赖到 app state
    # from your_app.main import _state
    # _state.model = mock_model
    # _state.db = mock_db

    # --- 占位 app（仅供模板可运行，实际使用时替换） ---
    from fastapi import FastAPI

    app = FastAPI()

    @app.get("/health")
    async def health():
        return {"status": "ok"}

    @app.post("/items")
    async def create_item(item: dict):
        return {"id": "item-001", **item}

    # --- 占位 app 结束 ---

    transport = ASGITransport(app=app)
    client = AsyncClient(transport=transport, base_url="http://test")

    yield client

    # 清理：重置注入的 mock 状态
    # _state.model = None
    # _state.db = None


# ============================================================================
# 2. 其他常用 fixture
# ============================================================================


@pytest.fixture
def sample_embedding() -> list[float]:
    """返回一个预计算的 768 维归一化嵌入向量。

    用于测试需要向量输入的端点（如相似度搜索）。
    【自定义】根据你的模型维度调整。
    """
    import math

    raw = [1.0] * 768
    magnitude = math.sqrt(sum(x * x for x in raw))
    return [x / magnitude for x in raw]


@pytest.fixture
def mock_external_service():
    """返回一个 mock 的外部服务客户端。

    【替换】根据你的外部依赖调整：
      - Milvus: client.search.return_value = [[hit]]
      - MongoDB: collection.find_one.return_value = {...}
      - COS: client.put_object.return_value = {"ETag": "..."}
    """
    client = MagicMock()
    client.query.return_value = [{"id": "001", "score": 0.95}]
    return client


# ============================================================================
# 3. 异步测试 — 基本 CRUD
# ============================================================================
# 项目约定：FastAPI 端点都是 async，测试也用 async。
# 需要 pytest-asyncio 插件和 @pytest.mark.asyncio 装饰器。


@pytest.mark.asyncio
async def test_health_returns_200(test_client):
    """GET /health 应返回 200 和 status=ok。

    这是最基本的健康检查测试，验证服务启动正常。
    """
    resp = await test_client.get("/health")

    # --- 状态码断言 ---
    assert resp.status_code == 200

    # --- 响应体断言 ---
    data = resp.json()
    assert data["status"] == "ok"


@pytest.mark.asyncio
async def test_create_item_returns_201_or_200(test_client):
    """POST /items 应创建资源并返回 id。

    【替换】根据你的 API 调整路径、请求体和断言。
    """
    payload = {"name": "test-item", "type": "sprite"}

    resp = await test_client.post("/items", json=payload)

    assert resp.status_code == 200  # 【替换】部分 API 返回 201
    data = resp.json()
    assert "id" in data
    assert data["name"] == "test-item"


# ============================================================================
# 4. 参数化测试 — 多场景覆盖
# ============================================================================
# 使用 @pytest.mark.parametrize 避免为每个输入写独立测试函数。
# pytest.param(..., id="...") 给每个用例命名，失败时更易定位。


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "endpoint,expected_status",
    [
        pytest.param("/health", 200, id="health-ok"),
        pytest.param("/nonexistent", 404, id="not-found"),
    ],
)
async def test_endpoint_status_codes(test_client, endpoint: str, expected_status: int):
    """验证不同端点返回预期的 HTTP 状态码。

    【自定义】添加你的路由和期望状态码。
    """
    resp = await test_client.get(endpoint)
    assert resp.status_code == expected_status


# ============================================================================
# 5. 使用 @patch mock 外部调用
# ============================================================================
# 当端点内部调用了外部服务（如 CLIP 推理、Milvus 搜索），
# 使用 @patch 替换这些调用，避免测试依赖外部环境。


@pytest.mark.asyncio
async def test_with_mocked_dependency(test_client):
    """展示如何在异步测试中使用 patch mock 外部依赖。

    【替换】将 patch 路径改为你的外部调用所在模块。
    """
    # 方式一：使用 patch 作为上下文管理器
    # with patch("your_app.services.clip.encode_image") as mock_encode:
    #     mock_encode.return_value = [0.1] * 768
    #     resp = await test_client.post("/embed", ...)
    #     assert resp.status_code == 200
    #     mock_encode.assert_called_once()

    # 方式二：使用 patch 装饰器（见下方 class 示例）
    pass


# ============================================================================
# 6. 类组织测试 — 按功能模块分组
# ============================================================================
# 当一个文件测试多个相关端点时，用 class 分组更清晰。


class TestHealthEndpoint:
    """健康检查端点的所有测试。"""

    @pytest.mark.asyncio
    async def test_returns_status_ok(self, test_client):
        """正常情况下返回 ok。"""
        resp = await test_client.get("/health")
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"

    # @pytest.mark.asyncio
    # async def test_returns_503_when_model_not_loaded(self, test_client):
    #     """模型未加载时返回 503。
    #
    #     【替换】根据你的健康检查逻辑调整。
    #     """
    #     with patch("your_app.main._state") as mock_state:
    #         mock_state.model = None
    #         resp = await test_client.get("/health")
    #         assert resp.status_code == 503


# ============================================================================
# 7. 辅助提示
# ============================================================================
#
# pytest 常用装饰器：
#   @pytest.mark.asyncio           — 标记异步测试（需要 pytest-asyncio）
#   @pytest.mark.parametrize(...)  — 参数化测试
#   @pytest.mark.skip(reason=...)  — 跳过测试
#   @pytest.mark.skipif(cond, ...) — 条件跳过
#
# pytest fixture 作用域：
#   @pytest.fixture                — 每个测试函数执行一次（默认 scope="function"）
#   @pytest.fixture(scope="module") — 每个测试模块执行一次
#   @pytest.fixture(scope="session") — 整个测试会话执行一次
#
# httpx AsyncClient 常用方法：
#   await client.get("/path")                    — GET 请求
#   await client.post("/path", json={...})       — POST JSON 请求
#   await client.put("/path", json={...})        — PUT JSON 请求
#   await client.delete("/path")                 — DELETE 请求
#   await client.post("/path", content=bytes)    — POST 二进制数据
#   await client.post("/path", files={"f": ...}) — POST 文件上传
#
# 响应对象常用属性：
#   resp.status_code   — HTTP 状态码
#   resp.json()        — 解析 JSON 响应体
#   resp.text          — 原始文本响应
#   resp.headers       — 响应头字典
#
# unittest.mock 常用方法：
#   MagicMock()                         — 创建 mock 对象
#   MagicMock(return_value=val)         — 设置同步返回值
#   MagicMock(side_effect=exc)          — 设置抛出异常
#   MagicMock(side_effect=[v1, v2])     — 设置多次返回值序列
#   patch("module.name")               — mock 指定对象
#   mock.assert_called_once()           — 断言被调用一次
#   mock.assert_called_with(args)       — 断言调用参数
#   mock.assert_not_called()            — 断言未被调用
#   mock.call_count                     — 获取调用次数
