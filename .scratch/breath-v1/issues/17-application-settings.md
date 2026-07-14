# 提供应用配置样式

Status: ready-for-agent

## Parent

[Breath v1 PRD](../spec.md)

## What to build

提供只影响终端之外应用界面的应用配置样式，并与 Agent 集成、已归档等管理页面及所有行为选项保持明确边界。

## Acceptance criteria

- [ ] 应用配置只改变终端外的界面样式并持久化
- [ ] 应用配置不改变 Shell、快捷键、分屏或 Agent 行为
- [ ] Agent 集成和已归档作为管理页面而非第三类配置
- [ ] 样式变化通过可观察 UI 行为测试

## Blocked by

- [01 打开第一个可持久化的原生终端](01-first-persistent-terminal.md)
