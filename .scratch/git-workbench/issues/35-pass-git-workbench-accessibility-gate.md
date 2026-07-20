# 通过 VoiceOver、键盘和系统辅助功能验收

Status: implementation-complete-pending-manual-acceptance

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

让完整 Git 工作台支持 VoiceOver、无鼠标操作、增强对比度、减少动态效果和应用字体设置，并为 Commit Graph 提供线性替代表示。

## Acceptance criteria

- [x] 工具栏、树、Graph、Diff 行、状态和操作按钮具有稳定可访问性语义
- [x] 状态不只依赖颜色
- [x] Commit Graph 提供按时间和拓扑描述的线性替代表示
- [x] 用户可纯键盘完成选择变更、审阅 Diff、填写消息和 Commit
- [x] 页面遵循增强对比度、减少动态效果和应用字体设置
- [x] 自动辅助功能测试通过
- [ ] VoiceOver、Merge Tool、复杂 Diff 和无鼠标流程完成人工验收

## Acceptance note

实现与自动化契约已完成。当前机器的 Orca runtime 无法启动，
`AXIsProcessTrusted()` 为 `false`，macOS 同时拒绝 `osascript` 辅助访问，
因此最后一项必须在获得 Accessibility 权限的验收环境中人工签字。

## Blocked by

- [33 提供 JetBrains 风格快捷键、焦点作用域与设置管理](33-configure-jetbrains-style-git-shortcuts.md)
