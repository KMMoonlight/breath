# 建立 Qwen Code 当前额度服务商查询

Status: ready-for-agent

## Parent

[Agent 额度检查](../spec.md)

## What to build

以 Qwen Code 建立多服务商 Agent 的完整额度路径：只识别 CLI 当前默认会使用的额度服务商和登录身份，查询该服务商的官方额度，不遍历备用或未启用凭据。

## Acceptance criteria

- [ ] Qwen Code 卡片识别并展示当前额度服务商名称
- [ ] 只读取当前有效身份所需配置，不遍历或查询已配置但未启用的 API Key
- [ ] 当前服务商有公开 API 或获授权的私有官方接口时优先查询，运行时失效则使用合规官方 CLI 或协议兜底
- [ ] 当前服务商返回多个额度池时全部展示，并保留百分比、剩余量、余额、速率限制和单位的官方语义
- [ ] 当前服务商无法确定、未登录或没有合规查询路径时进入对应状态
- [ ] 服务商与凭据只存在于查询内存中，失败原因不包含密钥、完整账号或配置内容
- [ ] 使用多组临时配置与响应样本覆盖当前服务商选择、备用凭据忽略和 BYOK
- [ ] 形成 OpenCode 和 Pi 可复用的当前额度服务商查询能力

## Blocked by

- [打通 Codex Agent 额度检查](01-query-codex-agent-quota.md)
