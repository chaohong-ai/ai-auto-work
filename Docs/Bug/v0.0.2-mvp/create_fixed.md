# 已修复bug

## 2026-03-13
- [x] 点击Start Creating创建游戏时，若用户已有活跃session（报错"user anonymous already has active session sess_xxx"），应跳转到对应的会话窗口而非报错
  - **根因**：前端 `request()` helper 在错误响应中只保留了 message 字符串，丢弃了 error code 和 details，导致 create 页面无法识别 SESSION_LIMIT_EXCEEDED 错误并提取 existing_session_id
  - **修复**：新增 `APIRequestError` class 保留完整错误信息；`create/page.tsx` 中检测冲突错误码后自动跳转到已有 session
