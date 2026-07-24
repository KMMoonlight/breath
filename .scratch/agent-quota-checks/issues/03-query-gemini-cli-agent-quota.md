# 通过合规官方路径查询 Gemini CLI Agent 额度

Status: ready-for-agent

## Parent

[Agent 额度检查](../spec.md)

## What to build

在不复用 Gemini CLI OAuth 访问其私有后端的前提下，通过官方 CLI 或官方协议读取当前身份可公开获得的额度；没有合规、只读且不消耗模型额度的查询路径时明确显示不支持。

## Acceptance criteria

- [ ] Gemini CLI 查询不会把 OAuth 凭据发送到第三方客户端调用的私有 Gemini 后端
- [ ] 存在官方只读 CLI 或协议路径时，展示其给出的剩余量、限制、百分比和重置信息，不自行换算
- [ ] 没有符合边界的路径时进入“不支持查询”，不尝试逆向绕过
- [ ] CLI 调用不发送模型提示、不消耗额度、不进入持续交互会话，原始输出只在内存中处理
- [ ] 文本解析固定输出语言，格式无法识别时直接展示脱敏失败
- [ ] 通过可控 CLI 响应测试可用、不支持、认证失败和格式变化
- [ ] Gemini CLI 状态独立更新，不影响其他 Agent 卡片

## Blocked by

- [打通 Codex Agent 额度检查](01-query-codex-agent-quota.md)
