# 将当前额度服务商查询扩展到 OpenCode

Status: implemented

## Parent

[Agent 额度检查](../spec.md)

## What to build

让 OpenCode 复用多服务商额度契约，只查询当前默认服务商和身份。当前服务商为 OpenCode 自有服务或 BYOK 服务时，展示其官方可用额度；未启用的其他提供商不参与查询。

## Acceptance criteria

- [x] OpenCode 卡片展示当前额度服务商，不枚举所有已配置提供商
- [x] 当前服务商具有合规额度来源时展示官方百分比、余额、消费上限或速率限制
- [x] BYOK 只查询当前有效 Key 对应服务商，备用 Key 不被读取或发送
- [x] 当前服务商没有查询能力时显示“不支持查询”，不使用本地 Token 或费用估算
- [x] 失败原因经过脱敏，不包含配置内容、完整账号或凭据
- [x] 使用临时配置和响应样本覆盖当前服务商、OpenRouter BYOK、无服务商与不支持
- [x] OpenCode 查询遵守并发、独立超时、取消和失败替换规则

## Blocked by

- [打通 Codex Agent 额度检查](01-query-codex-agent-quota.md)
- [建立 Qwen Code 当前额度服务商查询](05-query-qwen-code-quota-provider.md)

## Comments

- 2026-07-24：当前实现对 OpenRouter BYOK 使用公开额度接口；OpenCode 自有服务或其他服务商没有确认到合规官方额度来源时显示“不支持查询”。
