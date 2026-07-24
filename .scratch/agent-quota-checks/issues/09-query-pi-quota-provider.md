# 将当前额度服务商查询扩展到 Pi

Status: implemented

## Parent

[Agent 额度检查](../spec.md)

## What to build

让 Pi 复用当前额度服务商查询能力，只检查其默认模型服务商和身份，并展示该服务商官方提供的余额、限制或重置数据。

## Acceptance criteria

- [x] Pi 卡片识别并展示当前默认额度服务商
- [x] 只查询当前有效身份，不遍历其他已配置模型或 API Key
- [x] 官方网络接口优先，合规官方 CLI 或协议作为运行时兜底
- [x] 官方返回的余额、限制、百分比和重置时间按原始语义展示
- [x] 没有官方额度来源时显示“不支持查询”，不使用 Pi 的本地 Token 或成本统计估算
- [x] 失败文本与测试记录不包含 Key、完整账号或配置内容
- [x] 使用临时配置与响应样本覆盖默认服务商、OpenRouter BYOK、未登录和不支持

## Blocked by

- [打通 Codex Agent 额度检查](01-query-codex-agent-quota.md)
- [建立 Qwen Code 当前额度服务商查询](05-query-qwen-code-quota-provider.md)

## Comments

- 2026-07-24：当前实现对 OpenRouter BYOK 使用公开额度接口；其他默认服务商没有确认到合规官方额度来源时显示“不支持查询”。
