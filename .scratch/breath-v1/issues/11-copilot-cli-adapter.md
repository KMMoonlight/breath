# 支持 GitHub Copilot CLI Agent 适配器

Status: ready-for-agent

## Parent

[Breath v1 PRD](../spec.md)

## What to build

按共用 Agent 契约接入 GitHub Copilot CLI 官方 hooks、状态、官方元数据与恢复能力。

## Acceptance criteria

- [ ] 集成可显式启用、幂等更新和完整卸载
- [ ] 官方事件正确驱动四态并关联到唯一窗格
- [ ] 标题、会话标识和恢复能力按官方支持工作并正确降级
- [ ] 不解析终端输出且不传输对话内容
- [ ] Copilot CLI 契约测试通过

## Blocked by

- [08 用 Codex 打通首个完整 Agent 增强路径](08-codex-agent-integration.md)
