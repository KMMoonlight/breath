# 接入 GitHub Copilot CLI Agent 额度查询

Status: implemented

## Parent

[Agent 额度检查](../spec.md)

## What to build

通过 GitHub Copilot CLI 的官方 API、ACP 或只读命令查询当前账号额度，将官方返回的请求、AI Credits、余额或限制窗口原样接入统一额度卡片。

## Acceptance criteria

- [x] 已安装且已登录的 Copilot CLI 卡片展示当前账号官方提供的额度数据
- [x] 优先使用公开 API 或官方协议，必要时使用不消耗模型额度的官方只读 CLI 兜底
- [x] 请求数、AI Credits、余额和重置周期保留官方名称与单位，不强制转换为百分比
- [x] 个人、组织或企业身份没有可访问数据时显示未登录、不支持或脱敏失败中的正确状态
- [x] 不新增 GitHub 登录或 PAT 输入，也不展示完整账号身份
- [x] 使用协议与 API 响应样本覆盖成功、无权限、无额度字段和格式变化
- [x] Copilot 查询遵守独立超时、取消和失败替换旧结果规则

## Blocked by

- [打通 Codex Agent 额度检查](01-query-codex-agent-quota.md)
