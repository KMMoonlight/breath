# 完成 Agent 额度检查全矩阵发布门禁

Status: implementation-complete-pending-manual-acceptance

## Parent

[Agent 额度检查](../spec.md)

## What to build

把九个 Agent 的额度适配器作为一个完整页面通过发布验收：验证固定顺序、独立并发、超时与兜底、安全边界、响应式展示、本地化和辅助功能，确保新增或变更适配器不会静默破坏矩阵契约。

## Acceptance criteria

- [x] 支持注册表中的九个 Agent 都声明明确的额度能力；未安装项不创建卡片
- [x] 已安装卡片按注册表固定顺序展示，不按状态或额度动态排序
- [x] 全部刷新并发执行、单卡完成即更新、每条完整链路独立 15 秒超时且可取消
- [x] 单个 Agent 的未登录、不支持、失败或超时不阻断其他卡片
- [x] 网络接口运行时失败会尝试合规 CLI 或协议兜底，所有路径失败后才展示最终脱敏原因
- [x] 失败直接替换旧结果，应用重启后不恢复额度，离开页面后不轮询
- [x] 百分比才使用进度条并保留官方方向，其他额度只显示原始数值和单位
- [x] 警告色只响应官方警告语义，状态同时使用文字和图标
- [ ] 宽窄窗口、浅深色、本机时区、中英文、键盘和 VoiceOver 人工验收通过
- [x] 界面不展示查询来源、完成时间或内部兜底过程，额度页不提供安装、登录或凭据配置
- [x] 自动化安全测试证明令牌、完整账号和原始 CLI 输出不会进入持久化、日志、错误、崩溃报告或界面
- [ ] 完整 Swift 测试套件在单次进程中通过；额度检查的发布门禁已可独立运行

## Blocked by

- [接入 Claude Code Agent 额度查询](02-query-claude-code-agent-quota.md)
- [通过合规官方路径查询 Gemini CLI Agent 额度](03-query-gemini-cli-agent-quota.md)
- [接入 GitHub Copilot CLI Agent 额度查询](04-query-github-copilot-cli-agent-quota.md)
- [建立 Qwen Code 当前额度服务商查询](05-query-qwen-code-quota-provider.md)
- [接入 Cursor Agent 额度查询](06-query-cursor-agent-quota.md)
- [接入 Factory Droid Agent 额度查询](07-query-factory-droid-agent-quota.md)
- [将当前额度服务商查询扩展到 OpenCode](08-query-opencode-quota-provider.md)
- [将当前额度服务商查询扩展到 Pi](09-query-pi-quota-provider.md)

## Comments

- 2026-07-24：额度发布门禁通过；排除已知顺序相关 Ghostty 用例后，400 个测试在重跑中通过，该 Ghostty 用例单独运行也通过。单进程完整运行仍会在既有原生终端测试中出现 signal 11，保留人工界面验收与单进程全套稳定性为发布前门禁。
