# 手动运行第一条 Codex 自动化

Status: ready-for-agent

## Parent

[Breath 自动化](../spec.md)

## What to build

交付 Automation 的第一条完整可运行路径：用户从原任务入口进入自动化页面，创建一个绑定 Workspace、使用固定 Prompt 和 Codex 的“仅手动”自动化，点击“立即运行”后由 Codex 在真实 Workspace 的强制只读沙盒中无头执行，并在详情中看到持久化的最终回答。

本切片覆盖 PRD User Stories 1–6、13–18、23–26、44–45、93–107、127–134，同时建立后续管理、调度、队列、CLI 和其他 Agent 共用的公开自动化用例服务。实现过程中同步补充 Automation 领域词汇和 PRD 指定的架构记录。

## Acceptance criteria

- [ ] 活动栏原“任务”位置改为“自动化”，没有选中 Workspace 或 Work Session 时仍可进入；选择工作会话后沿用既有规则返回终端
- [ ] 没有 Workspace 时展示安静的引导空状态并禁用新建；已有 Workspace 且没有自动化时可以开始创建
- [ ] 用户可以创建名称、Workspace、固定多行 Prompt、Codex、仅手动触发和最大运行时长完整的自动化；名称、Workspace、Prompt 和 Agent 必填
- [ ] 自动化使用不展示的唯一 ID，创建后默认启用但不立即运行，并通过公开用例与 GRDB repository 在应用重启后恢复
- [ ] Codex 只有在已安装、达到兼容版本且具备自动化 Runner 契约时可选择；未安装时不显示，版本过旧时显示禁用原因
- [ ] “立即运行”直接以真实 Workspace 为工作目录启动 Codex，不创建 Work Session、Terminal Tab、Terminal Pane、Agent Conversation、Managed Worktree 或 Git 分支
- [ ] Codex 及其子进程受强制 macOS 进程沙盒约束：Workspace 与其他用户路径不可写，本次临时目录和临时 HOME 可写，出站网络可用，无法建立沙盒时在启动前失败
- [ ] 运行复用 Codex 既有认证、配置和全局 Skills，但 Breath 不解析、展示或持久化凭据；运行结束后销毁临时环境
- [ ] Codex 正常退出且产生非空最终回答时标记成功；启动失败、非零退出或空回答时标记失败并只保存清理后的摘要
- [ ] 详情展示运行状态和 Markdown 最终回答，复制操作返回原始文本，不提供“查看原文”、Diff、Artifact、文件应用或过程日志
- [ ] 公开自动化用例测试使用临时真实 SQLite 和 Workspace，验证创建、重启恢复、运行结果及项目文件保持不变；Codex Runner 与真实沙盒另有窄契约测试
- [ ] App Shell 验证覆盖入口替换、无 Workspace 空状态、创建表单、立即运行、结果详情、键盘和 VoiceOver 基本语义

## Blocked by

None - can start immediately
