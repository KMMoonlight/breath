# 恢复并管理长期 Note Agent Conversation

Status: implemented

## Parent

[Breath 全局 Markdown 笔记库与笔记 Agent 抽屉](../spec.md)

## What to build

完成 Note Agent 的长期会话体验：记住用户选择，安全切换正在运行的 Agent，只持久化 Agent 类型与官方 Session ID，并在下次启动时由用户选择继续或新建。隐藏抽屉通过按钮状态表达运行中或需要处理，抽屉宽度可调但有明确上限。

本切片覆盖 PRD User Stories 144、152、156、158–165。

## Acceptance criteria

- [ ] Breath 记住上次显式选择的受支持 Agent，并在下次打开空闲选择器时作为默认项；卸载或不兼容后不伪造可用状态
- [ ] 已有 Agent 运行时选择另一个 Agent 会先确认结束当前对话；取消确认保持当前进程和终端完全不变
- [ ] Breath 只持久化 Agent 类型、官方 Agent Session ID 和不含内容的生命周期状态，不保存提示词、回复、工具输入输出、转录或终端滚屏
- [ ] 应用重新启动后不自动启动 Note Agent；打开抽屉时在恢复信息有效的情况下提供“继续上次对话”和“开始新对话”
- [ ] “继续上次对话”通过对应 Agent Adapter 的官方恢复能力启动，失败后保留可重试或开始新对话的选择
- [ ] “开始新对话”不覆盖 CLI 自有历史，只更新 Breath 当前恢复绑定
- [ ] 明确“结束对话”会清除 Breath 恢复绑定，但不会删除 Agent CLI 自己保存的对话、配置或历史
- [ ] 抽屉隐藏时 Agent 按钮展示运行中或需要处理状态，并提供等价 VoiceOver 描述
- [ ] Agent 需要处理时不会自动展开抽屉、抢夺焦点、播放声音或发送 macOS 系统通知
- [ ] 抽屉默认宽度为 420pt，最小 340pt，最大为笔记页宽度 45% 与 720pt 中较小者
- [ ] 用户可以拖动调整宽度，窗口变窄时自动约束，经过约束的合理宽度跨重启恢复
- [ ] 应用退出协调同时处理脏 Note Tab 和运行中 Note Agent；任一取消退出动作都会保持应用和会话运行
- [ ] Agent 事件通过 Note Agent Conversation 身份关联，现有 Terminal Pane 会话恢复与事件关联保持不变
- [ ] 数据库原始内容检查确认没有 Agent 对话、终端内容、凭据或完整命令行落盘
- [ ] 公开用例和记录型 Adapter 覆盖切换确认、恢复成功/失败、新建、结束、应用退出、状态变化、宽度约束和隐私
- [ ] App Shell 验证覆盖继续/新建、按钮状态、无通知、窗口缩放、焦点、键盘和 VoiceOver 语义

## Blocked by

- [恢复未保存 Note Tab 并协调退出](06-recover-dirty-tabs-and-coordinate-exit.md)
- [在原生抽屉启动第一条 Note Agent Conversation](16-launch-first-note-agent-conversation.md)
