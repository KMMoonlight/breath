# 在原生抽屉启动第一条 Note Agent Conversation

Status: implemented

## Parent

[Breath 全局 Markdown 笔记库与笔记 Agent 抽屉](../spec.md)

## What to build

交付 Note Agent 的第一条完整终端路径：用户从 Notes 页右上角打开抽屉，从已安装且受支持的 Agent CLI 中显式选择一个，并在以 Note Library 为当前目录的真实原生终端中运行。抽屉隐藏或切换页面不终止进程，用户可以明确结束，应用完全退出时也会可靠停止。

本切片覆盖 PRD User Stories 139–151、153–155、157、166–167。开始实现前先补充 Agent 会话范围 ADR，把 Note Agent Conversation 和 Note Agent Terminal 纳入领域词汇及事件关联协议。

## Acceptance criteria

- [ ] Notes 页顶部最右侧提供 Agent 按钮；Note Library 可访问时即使没有打开笔记也可用，不可访问时禁用并说明原因
- [ ] 空闲抽屉使用与 Workspace 外部编辑器选择器一致的主按钮和菜单模式，只列出当前已安装且 Breath 支持的 Agent CLI
- [ ] 用户必须显式选择 Agent，Breath 不根据文件内容、Workspace 或上次终端自动猜测
- [ ] 选择后通过现有 Agent Adapter 在真实原生终端中启动 CLI，`cwd` 严格为经验证的 Note Library 根目录
- [ ] Note Agent Terminal 使用全局 Terminal Settings 的字体、字号、主题和光标，不消费 Markdown 主题
- [ ] CLI 保留自己的认证、权限确认、沙箱和命令能力；Breath 不额外设为只读
- [ ] Breath 不注入当前笔记路径、笔记正文、隐藏 Prompt 或其他未展示上下文
- [ ] 任一时刻最多存在一个 Note Agent Terminal 和一个 Note Agent Conversation
- [ ] 收起抽屉、切换 Activity Bar 页面或关闭窗口但应用仍运行时，Agent 进程继续运行
- [ ] “结束对话”在进程仍运行时先确认，确认后终止完整进程树、清理终端运行时并返回选择器
- [ ] 完全退出 Breath 时 Note Agent 纳入终止协调，确认退出后不会留下孤儿进程
- [ ] Agent 对 Note Library 的文件修改进入统一外部变化和冲突流程
- [ ] Note Agent 不创建或伪造 WorkspaceID、WorkSessionID 或 TerminalPaneID，也不出现在 Workspace、Session Tree、Git Workbench 或 Work Session 恢复中
- [ ] 新 ADR 定义可区分 Terminal Pane 与 Note Library 的 Agent 会话范围和事件关联键，同时保持现有事件兼容
- [ ] Agent 终端内的网络命令遵循 CLI 自身环境，不自动继承 Breath Network Proxy
- [ ] 公开用例与终端契约使用临时 Note Library 验证 CLI 过滤、启动目录、真实输入输出、隐藏、结束、应用退出、进程树和身份隔离
- [ ] App Shell 验证覆盖按钮、选择器、抽屉、禁用原因、终端焦点、结束确认、键盘和 VoiceOver 基本语义

## Blocked by

- [管理全局 Note Library 生命周期](02-manage-note-library-lifecycle.md)
- [处理外部文件变化与编辑冲突](07-reconcile-external-file-conflicts.md)
