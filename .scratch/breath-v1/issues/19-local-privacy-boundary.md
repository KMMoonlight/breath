# 强制执行本地数据与隐私边界

Status: ready-for-agent

## Parent

[Breath v1 PRD](../spec.md)

## What to build

把本地优先和数据最小化变成可验证的产品边界：严格事件白名单、最小数据库、用户级文件权限，并确保 v1 没有账户、同步、遥测或隐藏内容采集。

## Acceptance criteria

- [ ] 未允许的 Agent 事件字段被拒绝且不会持久化
- [ ] 数据库不包含终端输出、滚动历史、提示词、回复、工具内容、transcript 或凭据
- [ ] 数据库与 Socket 只允许当前用户访问
- [ ] 应用不要求账户，不提供云同步且没有遥测网络请求
- [ ] 隐私契约测试覆盖事件到持久化的完整路径

## Blocked by

- [08 用 Codex 打通首个完整 Agent 增强路径](08-codex-agent-integration.md)
