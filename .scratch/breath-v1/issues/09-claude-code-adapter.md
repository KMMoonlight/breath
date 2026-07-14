# 支持 Claude Code Agent 适配器

Status: implemented

## Parent

[Breath v1 PRD](../spec.md)

## What to build

按已建立的 Agent 契约接入 Claude Code 的官方 hooks、状态、官方元数据与恢复能力，并对缺失能力使用统一降级路径。

## Acceptance criteria

- [x] 用户级集成可安全启用、重复启用和卸载
- [x] 官方事件正确映射到 Breath 四态并关联到唯一窗格
- [x] 官方标题、会话标识和恢复能力按实际支持工作
- [x] 缺失能力使用占位标题或空 Shell，不解析终端输出
- [x] Claude Code 官方事件样例通过共用适配器契约测试

## Blocked by

- [08 用 Codex 打通首个完整 Agent 增强路径](08-codex-agent-integration.md)
