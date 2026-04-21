# Aippy API 完整规格（实测）

**数据来源**: 浏览器 Network 抓包 + JS Bundle 逆向  
**Base URL**: `https://api.aippy.ai`  
**Auth**: `Authorization: Bearer {token}`（JWT，存于 localStorage）  
**Content-Type**: `application/json`

---

## 通用响应结构

```json
{
  "code": 0,
  "msg": "ok",
  "data": { ... }
}
```

---

## 1. 用户认证

### POST /api/user/register
注册新账号

### POST /api/user/login
```json
// Request
{ "email": "xxx@xx.com", "password": "..." }

// Response
{ "code": 0, "data": { "token": "eyJ...", "uid": 123, ... } }
```

### GET /api/user/profile
获取当前用户信息

### GET /api/user/uid
获取当前用户 UID

### PUT /api/user/account/info
更新账号信息（昵称、头像等）

### GET /api/user/account/info
获取账号详情

### POST /api/user/password/find
找回密码（发送重置邮件）

### POST /api/user/password/reset
重置密码

### POST /api/user/activate
激活账号

### POST /api/user/reactivate
重新激活

---

## 2. 项目（游戏）管理

### POST /api/project
创建新项目，返回 projectId 和 siteId

**推测 Request Body**:
```json
{
  "name": "My Game",
  "prompt": "a simple clicker game"
}
```

**推测 Response**:
```json
{
  "code": 0,
  "data": {
    "projectId": 397431,
    "siteId": "2b233916-36e0-41de-a129-42f75a76e054",
    ...
  }
}
```

### GET /api/project/{id}
获取项目详情

### PUT /api/project
更新项目信息

### DELETE /api/project/{id}
删除项目

### GET /api/project?targetUid={uid}
获取某用户的项目列表

### GET /api/project/models
获取可用 AI 模型列表  
**实测响应**: `{"code":0,"msg":"ok","data":{"models":null}}`（未登录时返回 null）

### POST /api/project/agent
**核心 API** — AI 生成游戏（SSE 流式）

**Request**: POST, Content-Type: application/json, Accept: text/event-stream  
**Body** (推测):
```json
{
  "projectId": 397431,
  "chatId": "uuid",
  "chatType": 1,
  "message": "add a high score display",
  "auxiliaryLogs": [],
  "errorSnapshot": null
}
```

**SSE 事件流**:
```
data: {"card_type":"start","message":{...}}

data: {"card_type":"thinking","message":[{"content":"分析需求...","status":0}]}

data: {"card_type":"tool","message":[{"tool":[{"type":"write_file","input":{"path":"src/App.tsx","content":"..."}}],"status":0}]}

data: {"card_type":"tool","message":[{"tool":[{"type":"build_project"}],"status":1}]}

data: {"card_type":"deploy_project","message":[{"content":"https://xxx.aippy.live","status":1}]}

data: {"card_type":"end"}
```

### GET /api/project/agent/chat/history
获取对话历史

**Query Params**:
- `projectId`: number
- `offset`: number (分页)
- `sortOrder`: "asc" | "desc"

### PUT /api/project/chat/{id}
更新对话记录

### POST /api/project/publish
发布游戏到社区

**推测 Body**:
```json
{
  "projectId": 397431,
  "name": "My Game",
  "tags": "Click, RNG",
  "category": "dopamine"
}
```

### POST /api/project/share
生成分享链接

---

## 3. 内容 Feed（Template）

### GET /api/template/recommend
**核心 Feed API**

**Query Params**:
- `page`: number（当前"随机页"，实测返回 page=18247）
- `size`: number（默认 12）
- `category`: "hot" | "latest" | "mindless" | "brain_hack" | "unhinged" | "dopamine" | "send_this"
- `sortBy`: "likes" | "views" | "createTime"

**实测响应片段**:
```json
{
  "code": 0,
  "data": {
    "list": [{
      "id": 118772,
      "projectId": 397431,
      "name": "The Meme Soundboard",
      "siteId": "2b233916-36e0-41de-a129-42f75a76e054",
      "accessUrl": "https://2b233916-36e0-41de-a129-42f75a76e054.aippy.live?v=1776300676",
      "snapshot": "https://cdn.aippy.ai/image/screenshot_xxx.png?x-oss-process=style/thumbnail_middle",
      "likes": 44166,
      "views": 518712,
      "comments": 887,
      "category": "dopamine",
      "deviceCapability": ["haptic-feedback", "local-storage"],
      ...
    }],
    "size": 12,
    "page": 18247,
    "total": 218953
  }
}
```

### GET /api/template/category_v2
获取分类列表

**实测响应**:
```json
{
  "code": 0,
  "data": {
    "categories": [
      {"categoryName": "Hot", "categoryId": "hot", "coverImageUrl": ""},
      {"categoryName": "Latest", "categoryId": "latest", "coverImageUrl": ""},
      {"categoryName": "Mindless", "categoryId": "mindless", "coverImageUrl": ""},
      {"categoryName": "Brain Hack", "categoryId": "brain_hack", "coverImageUrl": ""},
      {"categoryName": "Unhinged", "categoryId": "unhinged", "coverImageUrl": ""},
      {"categoryName": "Dopamine", "categoryId": "dopamine", "coverImageUrl": ""},
      {"categoryName": "Send This", "categoryId": "send_this", "coverImageUrl": ""}
    ]
  }
}
```

### GET /api/template/info?templateId={id}
**关键字段**: `prompt` 字段存储完整 AI 对话摘要（structured summary 格式）

**实测 prompt 结构** (118772 游戏):
```
<summary>
1. Primary Request and Intent: ...
2. Key Technical Concepts: ...
3. Files and Code Sections: src/components/UsernamesSection.tsx, src/components/MemeSoundboard.tsx
4. Errors and fixes: ...
5. Problem Solving: ...
6. All user messages: ["message1", "message2", ...]
7. Pending Tasks: ...
8. Current Work: ...
9. Optional Next Step: ...
</summary>
```

### POST /api/template/view
记录游戏浏览（无需 body，URL 参数可能含 templateId）

### POST /api/template/like
点赞游戏

### POST /api/template/unlike
取消点赞

### POST /api/template/remix
Fork/Remix 游戏

### GET /api/template/favorites/list
获取收藏列表

### POST /api/template/report
举报内容

---

## 4. 社交系统

### POST /api/friend/follow
```json
{ "targetUid": 123 }
```

### POST /api/friend/unfollow
```json
{ "targetUid": 123 }
```

### GET /api/friend/follower?uid={uid}&page=&size=
粉丝列表

### GET /api/friend/following?uid={uid}&page=&size=
关注列表

### GET /api/user/recommend
推荐创作者（首页侧边栏）

### GET /api/message/list
站内消息列表

### GET /api/message/unread/count
未读消息数

### POST /api/message/read
标记消息已读

### POST /api/comment/publish
```json
{
  "templateId": 118772,
  "content": "Great game!"
}
```

### GET /api/comment/list?templateId={id}&page=&size=
评论列表

### GET /api/comment/replies?commentId={id}
评论回复

### POST /api/comment/reply
回复评论

### POST /api/comment/remove
删除评论

---

## 5. 媒体与 AI 工具

### POST /api/media/asset/upload
上传媒体素材（multipart/form-data）

响应包含 CDN URL：`cdn.aippy.ai/asset/{uuid}.{ext}`

### POST /api/media/asset/batchDelete
批量删除

### GET /api/media/asset/list
素材列表

### GET /api/media/asset/stats
素材统计

### POST /api/user/media/upload
用户头像等个人媒体上传

### POST /api/llmodel/prompt/enhance
AI Prompt 增强

**Request**:
```json
{ "prompt": "a clicker game" }
```

**Response**:
```json
{
  "code": 0,
  "data": {
    "enhancedPrompt": "Create an addictive clicker game with..."
  }
}
```

---

## 6. 支付与订阅

### GET /api/subscription/product/?productType=1
**实测响应**:
```json
[
  {"id":18692,"name":"Starter","credits":500,"price":0,"currency":"USD","subUnit":"month","unit":0,"vipLevel":0},
  {"id":18693,"name":"Explorer","platformProductId":"price_1RF9B5AsfbpdwUgqUGxh3VQe","credits":2000,"price":19,"vipLevel":1},
  {"id":18694,"name":"Builder","platformProductId":"price_1RF9CqAsfbpdwUgq5FR7MlDV","credits":5000,"price":49,"vipLevel":2},
  {"id":18695,"name":"Master","platformProductId":"price_1RF9E0AsfbpdwUgquEHZCI1c","credits":10000,"price":99,"vipLevel":3},
  {"id":18696,"name":"Team","platformProductId":"price_1RF9GYAsfbpdwUgqI9wrNqOe","credits":20000,"price":199,"vipLevel":4}
]
```

### POST /api/payment/order/create
创建 Stripe 订单

**推测 Body**:
```json
{ "productId": 18693 }
```

**推测 Response**:
```json
{ "clientSecret": "pi_xxx_secret_xxx" }
```

### GET /api/payment/subscription/plan
当前订阅计划详情

### GET /api/user/account/transaction/records
积分消费记录

### POST /api/user/attendance
每日签到（获取积分）

### GET /api/user/affiliate/info
推广/邀请码信息

---

## 7. 认证机制

- **Token 存储**: `localStorage`（JS bundle 中读取 `localStorage.getItem(...)` 获取 token）
- **请求头**: `Authorization: Bearer {token}` + `withCredentials: true`
- **OAuth**: Google OAuth + Apple Sign In（前端跳转，后端换 token）
- **Token 刷新**: 自动 refresh 机制（JS bundle 含 `refreshTimer`、`inflightRequest` 模式）
- **SSE 专用 Headers**: `createSSEHeaders(token)` 函数单独生成
