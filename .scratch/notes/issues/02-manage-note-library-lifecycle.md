# 管理全局 Note Library 生命周期

Status: implemented

## Parent

[Breath 全局 Markdown 笔记库与笔记 Agent 抽屉](../spec.md)

## What to build

完成全局 Note Library 的生命周期：首次进入可以选择现有目录或创建目录，之后可以从 Notes 设置切换目录；目录暂时不可用时保留用户选择并提供恢复动作。切换只改变 Breath 的引用，不移动、复制、删除或自动重建原目录。

本切片覆盖 PRD User Stories 3、6–10、12、108、131。

## Acceptance criteria

- [ ] 首次进入 Notes 时可以选择现有目录或创建新目录；取消选择不会创建默认库或修改其他应用状态
- [ ] Breath 在任一时刻只有一个当前 Note Library，并通过 Notes 设置展示其真实路径和可访问状态
- [ ] 用户可以从 Notes 设置选择另一个目录；成功切换只更新库引用，不移动、复制或删除旧库内容
- [ ] 切换前通过统一未保存文档协调器处理当前脏标签；用户取消或任一必须保存的文档写入失败时保持旧库
- [ ] 新库完成边界验证和初始扫描后才提交切换，失败不会留下半切换的标签、索引或设置状态
- [ ] 当前目录不可访问时保留原路径和恢复元数据，Notes 页面提供“重试”“在 Finder 中显示”和“更换目录”
- [ ] Breath 不会因为路径失联而在旧位置创建空目录，也不会自动选择相似路径或迁移内容
- [ ] Note Library 引用、侧边栏基础偏好和切换状态由 Notes 仓库持久化，文件正文仍以真实文件为事实来源
- [ ] 切换完成后关闭旧库标签并发布明确的库变更事件，供后续搜索索引、文件监控和 Agent 生命周期清理派生状态
- [ ] Note Library 始终不进入 Workspace 列表、Session Tree、Work Session 恢复或 Git Workbench
- [ ] 使用两个临时真实目录和不可访问目录覆盖首次选择、创建、切换、取消、保存失败、权限变化、重启恢复和绝不搬移数据
- [ ] App Shell 验证覆盖首次引导、Notes 设置、脏标签阻塞、失联恢复动作、本地化、键盘和 VoiceOver 语义

## Blocked by

- [打开并显式保存第一篇全局 Note Document](01-open-and-save-first-global-note.md)
