# 接入 Cursor Agent 额度查询

Status: ready-for-agent

## Parent

[Agent 额度检查](../spec.md)

## What to build

查询 Cursor Agent 当前登录账号的官方用量、余额或限制。公开接口优先；没有公开接口时，只在服务商允许且使用获授权的情况下调用从官方客户端行为确认的接口，并以官方 CLI 作为合规兜底。

## Acceptance criteria

- [ ] 已安装且已登录的 Cursor Agent 卡片展示官方提供的当前额度数据
- [ ] 私有官方接口只有在服务商未禁止且凭据使用获授权时才可调用
- [ ] 网络接口不可用时，同一次刷新尝试不消耗模型额度的官方 CLI 或协议
- [ ] 费用、请求数、百分比和余额保留官方单位与方向，不做跨 Agent 比较
- [ ] 未登录、不支持和查询失败状态可区分，错误文本经过脱敏
- [ ] 通过响应样本覆盖成功、认证失效、接口变化和 CLI 兜底
- [ ] Cursor 查询结果不持久化，失败不保留旧数据

## Blocked by

- [打通 Codex Agent 额度检查](01-query-codex-agent-quota.md)
