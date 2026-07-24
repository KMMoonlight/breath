# 接入 Factory Droid Agent 额度查询

Status: ready-for-agent

## Parent

[Agent 额度检查](../spec.md)

## What to build

把 Factory Droid 的官方滚动额度窗口接入额度卡片，优先查询官方网络数据，并在需要时通过不消耗模型额度的官方限制命令读取额度。

## Acceptance criteria

- [ ] Factory Droid 卡片分别展示官方提供的滚动额度窗口，不合并五小时、周、月或其他池
- [ ] 百分比、剩余量、余额和重置时间严格沿用官方字段
- [ ] 网络接口运行时失效时使用官方只读限制命令兜底
- [ ] CLI 输出固定语言、仅在内存解析，不进入持续交互或发送模型提示
- [ ] 部分窗口或字段有效时展示已有内容，不因缺失字段丢弃整张卡片
- [ ] 未登录、不支持、超时和解析失败状态明确且脱敏
- [ ] 使用响应与 CLI 样本覆盖多个窗口、部分字段和格式变化

## Blocked by

- [打通 Codex Agent 额度检查](01-query-codex-agent-quota.md)
