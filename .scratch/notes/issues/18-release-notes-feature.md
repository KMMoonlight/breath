# 通过 Notes 发布质量门槛

Status: release-validation-pending

## Parent

[Breath 全局 Markdown 笔记库与笔记 Agent 抽屉](../spec.md)

## What to build

对完整 Notes 功能执行发布前收口，不新增产品行为。验证 PRD User Stories 1–167 已通过公开用例、真实文件系统、真实 WebKit、真实持久化和原生终端边界覆盖，并完成资源许可证、隐私、安全、性能、故障恢复、本地化和无障碍门槛。

## Acceptance criteria

- [ ] PRD User Stories 1–167 均能映射到至少一个已通过的行为测试或经记录的原生交互验收
- [ ] Notes 领域词汇、WebView 限定例外 ADR 和 Note Agent 会话范围 ADR 已完成评审，代码中没有伪造 Workspace、Work Session 或 Terminal Pane
- [ ] 从此前发布数据库升级到 Notes 模式成功，迁移失败可恢复，Note Library 文件永远不被迁移过程改写
- [ ] 数据库文件权限和原始内容隐私扫描通过；Agent 提示词、回复、工具输入输出、终端内容、凭据和完整命令行不落盘
- [ ] 笔记正文只出现在源文件、明确批准的崩溃恢复快照和可重建全文索引中
- [ ] Tiptap、Markdown 扩展、语法高亮、数学、Mermaid、主题、字体和图片均固定版本、离线可用且没有 CDN 引用
- [ ] 六套内置主题及所有第三方脚本、CSS、字体和图片完成许可证与归属审计；不可直接分发的视觉资源已由获准实现替代
- [ ] 安全语料确认 HTML、Mermaid、链接、本地资源、符号链接和远程网络请求不能越过已定义边界
- [ ] 性能基准记录首次打开、键入、标签切换、保存、全文搜索、索引重建和目录事件收敛，并通过已评审门槛
- [ ] 故障注入覆盖磁盘写满、权限变化、文件并发移动、索引损坏、WebView 进程退出和 Agent 异常退出，不发生静默截断或缓冲区丢失
- [ ] 应用退出、切库、批量关闭、删除脏文件和运行中 Note Agent 的组合状态全部收敛到 PRD 指定结果
- [ ] 所有 Notes 入口、文件树、标签、搜索、设置、冲突、恢复和 Agent 抽屉完成中英文、本地化、键盘和 VoiceOver 验收
- [ ] 状态表达不只依赖颜色；Light/Dark、窗口缩放和最小可用尺寸下没有不可达操作
- [ ] Notes 不引入账户、后端、同步、遥测、Git UI、替换、主题导入、版本历史或其他 Out of Scope 能力
- [ ] 全量测试套件和发布构建通过，打包应用在断网环境中可以编辑、保存、搜索和使用全部本地主题
- [ ] 发布验收结果记录任何已知限制；未满足源码保真、安全、许可证或数据完整性门槛时不得以降级承诺绕过发布阻塞

## Blocked by

- [安全重命名和移动文件并改写相对链接](09-rename-move-and-rewrite-links.md)
- [恢复未保存 Note Tab 并协调退出](06-recover-dirty-tabs-and-coordinate-exit.md)
- [打开相对链接并导入笔记附件](10-follow-links-and-import-attachments.md)
- [搜索当前 Note Document 和整座 Note Library](13-search-note-document-and-library.md)
- [应用内置 Markdown 主题和写作偏好](14-apply-built-in-themes-and-writing-preferences.md)
- [安全打开大型和复杂 Markdown 文档](15-open-large-complex-markdown-safely.md)
- [恢复并管理长期 Note Agent Conversation](17-resume-and-manage-note-agent-conversation.md)
