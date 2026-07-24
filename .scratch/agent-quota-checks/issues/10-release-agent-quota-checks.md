# 完成 Agent 额度检查全矩阵发布门禁

Status: ready-for-agent

## Parent

[Agent 额度检查](../spec.md)

## What to build

把九个 Agent 的额度适配器作为一个完整页面通过发布验收：验证固定顺序、独立并发、超时与兜底、安全边界、响应式展示、本地化和辅助功能，确保新增或变更适配器不会静默破坏矩阵契约。

## Acceptance criteria

- [ ] 支持注册表中的九个 Agent 都声明明确的额度能力；未安装项不创建卡片
- [ ] 已安装卡片按注册表固定顺序展示，不按状态或额度动态排序
- [ ] 全部刷新并发执行、单卡完成即更新、每条完整链路独立 15 秒超时且可取消
- [ ] 单个 Agent 的未登录、不支持、失败或超时不阻断其他卡片
- [ ] 网络接口运行时失败会尝试合规 CLI 或协议兜底，所有路径失败后才展示最终脱敏原因
- [ ] 失败直接替换旧结果，应用重启后不恢复额度，离开页面后不轮询
- [ ] 百分比才使用进度条并保留官方方向，其他额度只显示原始数值和单位
- [ ] 警告色只响应官方警告语义，状态同时使用文字和图标
- [ ] 宽窄窗口、浅深色、本机时区、中英文、键盘和 VoiceOver 验收通过
- [ ] 界面不展示查询来源、完成时间或内部兜底过程，额度页不提供安装、登录或凭据配置
- [ ] 自动化安全测试证明令牌、完整账号和原始 CLI 输出不会进入持久化、日志、错误、崩溃报告或界面
- [ ] 完整 Swift 测试套件通过，额度检查的发布门禁可独立运行

## Blocked by

- [接入 Claude Code Agent 额度查询](02-query-claude-code-agent-quota.md)
- [通过合规官方路径查询 Gemini CLI Agent 额度](03-query-gemini-cli-agent-quota.md)
- [接入 GitHub Copilot CLI Agent 额度查询](04-query-github-copilot-cli-agent-quota.md)
- [建立 Qwen Code 当前额度服务商查询](05-query-qwen-code-quota-provider.md)
- [接入 Cursor Agent 额度查询](06-query-cursor-agent-quota.md)
- [接入 Factory Droid Agent 额度查询](07-query-factory-droid-agent-quota.md)
- [将当前额度服务商查询扩展到 OpenCode](08-query-opencode-quota-provider.md)
- [将当前额度服务商查询扩展到 Pi](09-query-pi-quota-provider.md)
