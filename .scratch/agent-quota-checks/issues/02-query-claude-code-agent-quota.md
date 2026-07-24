# 接入 Claude Code Agent 额度查询

Status: implemented

## Parent

[Agent 额度检查](../spec.md)

## What to build

把 Claude Code 当前登录身份接入 Agent 额度检查。优先查询获授权的官方网络接口，运行时失效则使用不消耗模型额度的官方只读 CLI 或协议兜底，并沿用首条切片的安全与展示契约。

## Acceptance criteria

- [x] 已安装且已登录的 Claude Code 卡片展示官方返回的全部额度窗口、原始计量方式和重置时间
- [x] 查询顺序遵守公开 API、获授权私有官方接口、官方 CLI 或协议的优先级
- [x] CLI 文本兜底只运行官方只读额度或状态命令，固定输出语言，不发送模型提示或进入持续交互会话
- [x] 未登录、不支持和全部路径失败分别进入正确状态，失败原因经过脱敏
- [x] 官方账号身份存在时只展示遮罩值，不从凭据推断账号
- [x] 网络、CLI 和解析路径使用确定性响应样本覆盖成功、部分字段、认证失败与格式变化
- [x] Claude Code 失败不阻断其他 Agent，也不保留旧额度

## Blocked by

- [打通 Codex Agent 额度检查](01-query-codex-agent-quota.md)
