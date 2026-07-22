---
status: proposed
---

# 使用 Keychain 加密浏览器 Storage State

Breath 只把每个 Agent 对话浏览器配置档案中的 Cookie 和 Local Storage 导出为独立 Storage State，并使用该 Agent 对话的随机密钥加密落盘，密钥保存在 macOS Keychain。创建对应 Browser Context 时才把状态解密到当前用户可访问的临时位置，导入后立即删除明文；Agent 不能读取 Cookie 值。不同 Agent 对话的 Storage State 和密钥互不共享，并在 Agent 对话或其工作会话永久删除时一并删除。Breath 不持久化完整 Chromium Profile、浏览历史、缓存、IndexedDB 或 Service Worker 状态，以换取明确的敏感数据边界、可删除性和浏览器引擎可替换性，并接受少数网站无法完整恢复登录状态的限制。
