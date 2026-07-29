# 应用内置 Markdown 主题和写作偏好

Status: implemented

## Parent

[Breath 全局 Markdown 笔记库与笔记 Agent 抽屉](../spec.md)

## What to build

交付 Notes 外观与写作偏好：内置 GitHub、Gothic、Newsprint、Night、Pixyll、Whitey 六套 Typora 风格主题，按 Breath 当前 Light/Dark 外观自动选择兼容版本；Notes 设置同时控制代码行号和不自动更正的正文拼写检查。

本切片覆盖 PRD User Stories 88、95–97、131–138。

## Acceptance criteria

- [ ] 应用包内提供 GitHub、Gothic、Newsprint、Night、Pixyll 和 Whitey 六套离线 Markdown 主题资源
- [ ] 每套主题在资源注册阶段自动分类为 Light 或 Dark，运行时不要求用户手工标记
- [ ] Light 与 Dark 分别记住最近选择，首次默认 GitHub Light 和 Night Dark
- [ ] Breath 外观变化时编辑器切换到对应外观的已选主题，不修改 Markdown、选择区、撤销历史或滚动位置
- [ ] Notes 设置可以查看和选择当前外观可用主题，并明确不提供主题导入、自定义 CSS、社区下载或自动更新
- [ ] 主题 CSS、字体、图片和脚本完全随应用离线提供，不包含 CDN 或运行时下载引用
- [ ] 代码块行号设置默认关闭，切换后应用到所有 Note Tab 的展示层且不改写源码
- [ ] 正文拼写检查默认开启，只显示下划线且不自动更正
- [ ] 拼写检查忽略代码、链接、Front Matter、数学公式和 Mermaid，并可从 Notes 设置关闭
- [ ] Markdown 主题不改变 Agent 抽屉终端；Note Agent 继续消费全局 Terminal Settings
- [ ] 主题切换和设置变化通过 Notes 偏好仓库跨重启恢复，不进入 Markdown 文件
- [ ] 主题在常见 CommonMark、GFM、代码、表格、数学、Mermaid、HTML 和图片语料上保持可读和完整焦点状态
- [ ] 打包资源测试确认六套主题齐全、分类完整、无外部引用，并只包含获准分发或 Breath 自有的实现
- [ ] App Shell 与真实 WebKit 验证外观切换、设置持久化、拼写排除、代码行号、键盘和 VoiceOver 语义

## Blocked by

- [交互编辑代码块、表格和任务列表](11-edit-code-tables-and-task-lists.md)
- [安全渲染数学公式、Mermaid、HTML 和远程资源](12-render-math-mermaid-html-and-remote-resources.md)
