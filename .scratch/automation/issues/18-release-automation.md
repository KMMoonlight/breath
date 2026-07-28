# 完成 Automation 跨 Agent 发布验收

Status: ready-for-agent

## Parent

[Breath 自动化](../spec.md)

## What to build

完成 Automation 的跨切片集成、支持矩阵契约和发布验收。九个受支持 Agent、七类触发、只读运行沙盒、并发队列、应用生命周期、最近五次结果和未读角标必须作为一个一致产品工作，并满足键盘、VoiceOver、本地化及“不创建会话或修改项目”的边界。

本切片覆盖 PRD User Stories 153–155，并复核全部 PRD User Stories 的集成行为；它不增加 PRD 之外的新能力。

## Acceptance criteria

- [ ] Codex、Claude Code、Gemini CLI、GitHub Copilot CLI、Qwen Code、Cursor Agent、Factory Droid、OpenCode 和 Pi 全部通过统一 Automation Runner 支持矩阵契约
- [ ] 新增或修改受支持 Agent 时，缺少安装检测、最低版本、无头执行、最终回答、取消或沙盒契约会使测试失败
- [ ] 仅手动、单次、每日、每周、Interval、五字段 Cron 和外部短码七类触发都通过公开自动化用例服务进入同一并发与状态机
- [ ] 真实临时 SQLite 的集成测试覆盖创建、编辑、重启恢复、触发、队列、取消、错过、历史淘汰、未读和删除，不建立平行业务实现
- [ ] 真实 macOS 沙盒回归验证 Workspace 及其他用户路径不可写、临时 HOME 可写、Agent 配置中的 Unix Socket 等特殊文件被安全跳过、Codex 不创建被拒绝的嵌套沙盒、子进程继承限制、出站网络策略、入站监听拒绝和 fail closed
- [ ] App Shell 验证覆盖原任务入口替换、无 Workspace 时仍可创建、本地化未命名、标题解释 tooltip、可用 Agent 不显示错误警告、无自动化时的安静空白列表、无搜索结果时的紧凑行提示、双栏搜索与详情标题栏等高对齐、标题与启用状态同行、窄窗口、表单、列表、详情、历史、终态固定结束时间、角标和全部状态
- [ ] 全部新增操作可以通过键盘完成，VoiceOver 能读出名称、状态、禁用原因、计划、未读数量和确认影响，状态不只依赖颜色
- [ ] 中英文资源包含全部新增键、参数化错误、时间与数量文本；Agent 产品名、Cron 和 CLI 命令不被错误翻译
- [ ] 人工验收覆盖真实日历计划、Interval、Cron、`breath trigger`、窗口关闭、应用退出、系统睡眠、两个并行 Agent、排队取消和短码废止
- [ ] 人工验收确认自动化不创建 Work Session、Terminal Tab、Terminal Pane、Agent Conversation、Managed Worktree 或 Git 分支
- [ ] 人工验收确认 Agent 不能修改已跟踪、未跟踪或嵌套 Workspace 文件，所有终止路径均销毁临时目录且不留下孤儿进程
- [ ] 人工验收确认只保存最终回答与最小元数据、每个自动化只保留最近五次、没有“查看原文”、Diff、Artifact 或系统通知
- [ ] macOS 14 arm64 Debug 构建、自动化模块测试、Persistence 测试、Agent 契约测试和 App Shell 验证全部通过
- [ ] 领域词汇和架构记录与最终实现一致，PRD 保持 `ready-for-agent` 且不因发布验收被关闭或改写

## Blocked by

- [管理自动化清单与依赖状态](02-manage-automation-library-and-dependencies.md)
- [安全地取消、超时和中断自动化运行](03-control-timeout-sleep-and-interruption.md)
- [展示最近五次结果与未读角标](04-show-five-results-and-unread-badge.md)
- [按全局并发上限排队运行自动化](05-queue-runs-by-global-concurrency.md)
- [按单次、每日和每周计划运行自动化](06-run-on-once-daily-and-weekly-schedules.md)
- [按固定间隔运行自动化](07-run-on-fixed-intervals.md)
- [使用五字段 Cron 运行自动化](08-run-with-five-field-cron.md)
- [通过 breath trigger 短码触发自动化](09-trigger-with-breath-shortcode.md)
- [支持 Claude Code 自动化运行](10-support-claude-code-automation.md)
- [支持 Gemini CLI 自动化运行](11-support-gemini-cli-automation.md)
- [支持 GitHub Copilot CLI 自动化运行](12-support-github-copilot-cli-automation.md)
- [支持 Qwen Code 自动化运行](13-support-qwen-code-automation.md)
- [支持 Cursor Agent 自动化运行](14-support-cursor-agent-automation.md)
- [支持 Factory Droid 自动化运行](15-support-factory-droid-automation.md)
- [支持 OpenCode 自动化运行](16-support-opencode-automation.md)
- [支持 Pi 自动化运行](17-support-pi-automation.md)
