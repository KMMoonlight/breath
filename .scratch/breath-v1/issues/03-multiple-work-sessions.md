# 管理多个工作会话并保持后台运行

Status: ready-for-agent

## Parent

[Breath v1 PRD](../spec.md)

## What to build

让一个工作区拥有多个工作会话，并通过会话树切换。已实例化会话切走后继续运行，关闭唯一主窗口也不终止应用或终端，重新打开可继续交互。

## Acceptance criteria

- [ ] 一个工作区可以创建并展示多个工作会话
- [ ] 单窗格会话树只展示工作区与工作会话两级
- [ ] 切换工作会话不会停止离开的 Shell
- [ ] 关闭主窗口后进程继续运行，重新打开后可继续交互
- [ ] 会话选择与运行效果通过工作台用例边界测试

## Blocked by

- [01 打开第一个可持久化的原生终端](01-first-persistent-terminal.md)
