# 打开并显式保存第一篇全局 Note Document

Status: implemented

## Parent

[Breath 全局 Markdown 笔记库与笔记 Agent 抽屉](../spec.md)

## What to build

交付 Notes 的第一条完整编辑路径：用户从 Activity Bar 进入全局 Notes 页面，选择一个现有本地目录作为 Note Library，从基础文件树打开一篇 Markdown，在单个共享的 Tiptap 编辑画布中以所见即所得或源码模式编辑，并通过 `Cmd-S` 原子保存。该切片建立后续文件管理、标签、Markdown 扩展和 Agent 抽屉共用的 Notes 领域边界与公开用例服务。

本切片覆盖 PRD User Stories 1–5、11–13、16–17、41、58–61、73–76、83、85、99–100、126、128–130。开始实现前先补充 ADR 0006 的限定例外，并把 Note Library、Note Document 和 Note Tab 纳入领域词汇。

## Acceptance criteria

- [ ] Activity Bar 提供全局“笔记”入口；无需当前 Workspace 或 Work Session 即可进入，进入后不显示 Session Tree
- [ ] 用户可以选择一个现有本地目录作为全局唯一 Note Library，选择结果通过公开 Notes 用例和持久化仓库跨重启恢复
- [ ] Note Library 不创建 Workspace、Work Session、Terminal Pane 或 Git Workbench 状态，也不会出现在对应导航中
- [ ] 基础文件树从真实目录读取 Markdown 文件，忽略点文件和所有符号链接，并在打开时再次验证目标位于 Note Library 边界内
- [ ] `.md` 和 `.markdown` 文件在顶部打开固定 Note Tab，同一规范化文件最多一个标签，再次点击只聚焦已有标签
- [ ] 编辑画布使用一个共享 `WKWebView`，加载固定版本且完全离线打包的 Tiptap Core 与 Breath Markdown 桥，不为每个标签创建 WebView
- [ ] 默认显示 Typora 风格单画布所见即所得；`Cmd-/` 在当前标签切换完整源码模式，重新打开时默认回到所见即所得
- [ ] 编辑只修改内存缓冲区并在标签标题显示 `*`；不会自动覆盖源文件
- [ ] `Cmd-S` 通过同目录临时写入和原子替换保存当前文档；成功清除 `*`，失败保留缓冲区、标签和可操作错误
- [ ] 撤销回到最后保存的精确内容时 `*` 消失，重做改动后重新出现
- [ ] `Cmd-W` 关闭当前 Note Tab；`Cmd-T` 和 `Cmd-1` 至 `Cmd-9` 在 Notes 页面不创建或切换任何对象，离开 Notes 后现有快捷键保持不变
- [ ] WebView 只能加载受控的应用资源和经原生层验证的 Note Library 内容，不能通过任意文件 URL 读取其他本地目录
- [ ] 新 ADR 明确 WebView 例外只限于 Notes Markdown 编辑画布，Activity Bar、文件树、标签、对话框和终端继续使用原生 UI
- [ ] 使用临时真实 Note Library、真实持久化和真实 WebKit 契约验证启动恢复、打开、编辑、撤销、原子保存、保存失败、共享实例和边界保护
- [ ] App Shell 验证覆盖全局入口、Session Tree 隐藏、标签 `*`、快捷键上下文、键盘焦点和 VoiceOver 基本语义

## Blocked by

None - can start immediately
