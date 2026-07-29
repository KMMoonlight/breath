# 搜索当前 Note Document 和整座 Note Library

Status: implemented

## Parent

[Breath 全局 Markdown 笔记库与笔记 Agent 抽屉](../spec.md)

## What to build

交付两种明确分离的搜索：`Cmd-F` 在当前文档中定位，`Cmd-Shift-F` 通过本地可重建全文索引搜索整座 Note Library。结果展示路径、片段和行号并能打开定位；界面不提供当前或跨文件替换。

本切片覆盖 PRD User Stories 117–124、127。

## Acceptance criteria

- [ ] `Cmd-F` 在当前 Note Document 内搜索并前后定位匹配，不改变源码或脏状态
- [ ] `Cmd-Shift-F` 打开全库搜索，搜索 Markdown 和文本文件正文以及 Front Matter 原始文本
- [ ] 搜索结果展示文件路径、匹配片段和行号，点击后打开或聚焦 Note Tab 并定位匹配
- [ ] 当前和全库搜索都不提供替换、全部替换或仅替换模式
- [ ] 全文索引使用本地可重建存储，文件正文仍以 Note Library 文件为事实来源
- [ ] 初次建库、Breath 自己保存和外部文件变更会增量更新索引，并对批量事件收敛到最终磁盘状态
- [ ] 索引未就绪、正在重建、损坏或权限失败时显示明确状态，不返回看似完整的过期结果
- [ ] Notes 设置提供“重建索引”，重建可以取消或失败恢复，不影响源文件与 Note Tab
- [ ] 切换 Note Library 后删除旧库的全文索引和排队索引任务，再为新库建立独立索引
- [ ] Front Matter 中的 `tags` 可以按普通文本命中，但不会生成标签数据库、标签过滤器或专用导航
- [ ] 点文件、符号链接和 Note Library 外部内容不会进入索引
- [ ] 索引和查询完全留在本机，不调用账户、后端、同步服务或遥测
- [ ] 使用真实临时 SQLite 和 Note Library 覆盖初建、增量更新、外部变化、重建、损坏、切库清理、Unicode 和行定位
- [ ] App Shell 验证覆盖两个快捷键、结果片段、定位、索引状态、无替换入口、键盘和 VoiceOver 语义

## Blocked by

- [浏览 Note Library 文件树与文档大纲](03-browse-note-library-tree-and-outline.md)
- [处理外部文件变化与编辑冲突](07-reconcile-external-file-conflicts.md)
