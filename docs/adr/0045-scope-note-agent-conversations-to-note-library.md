# 将 Note Agent Conversation 关联到 Note Library

Notes 抽屉中的 Agent CLI 使用真实原生终端，以当前 Note Library 根目录作为工作目录，但不创建 Workspace、Work Session 或 Terminal Pane。Breath 为它建立独立的 Note Agent Conversation 和 Note Agent Terminal 身份，并让 Agent 事件携带可区分的会话范围：既有工作会话事件继续关联 Workspace、Work Session 和 Terminal Pane，Notes 事件只关联当前 Note Library 会话身份。任何实现都不得用伪造的 WorkspaceID、WorkSessionID 或 TerminalPaneID 复用旧路径。

一个 Note Library 同时最多拥有一条由 Breath 管理的 Note Agent Conversation。Breath 只持久化 Agent 类型和官方 Agent Session ID；隐藏抽屉或关闭窗口不停止进程，明确结束或完全退出应用才停止。该决定扩展 ADR 0010 和 ADR 0017 的关联范围，并继续遵守 ADR 0011 的最小 Agent 数据原则。
