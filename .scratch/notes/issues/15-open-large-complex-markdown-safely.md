# 安全打开大型和复杂 Markdown 文档

Status: implemented

## Parent

[Breath 全局 Markdown 笔记库与笔记 Agent 抽屉](../spec.md)

## What to build

让共享 WebView 编辑器在大型或复杂 Markdown 上保持可预测：通过真实基准确定安全阈值，超过阈值默认进入完整源码模式并允许用户手动尝试所见即所得；同时把源码保真、中文输入法、标签切换和 WebView 进程恢复提升为发布级契约。

本切片覆盖 PRD User Stories 69–72、79–80、85。

## Acceptance criteria

- [ ] 以文件大小、结构节点数、表格规模、数学、Mermaid 和 HTML 复杂度建立可重复基准，不只依据字节数猜测阈值
- [ ] 超过经测量的安全阈值时完整加载文档并默认进入源码模式，说明原因但不拒绝、截断或静默丢弃内容
- [ ] 用户可以手动尝试所见即所得；失败或资源压力只回退展示模式，不修改源文件和内存缓冲区
- [ ] 单个共享 WebView 在大量轻量 Note Tab 间切换，不为后台标签保留独立页面运行时
- [ ] 标签快速切换、解析取消和迟到消息不会串文档、丢选择区或错误改变脏状态
- [ ] 中文及其他组合输入法在所见即所得和源码模式中正确处理 composition、候选确认、光标和撤销边界
- [ ] 完整语料对所有已支持语法验证零改动零差异和局部改动最小差异，包括大文件与混合换行
- [ ] WebView 内容进程异常退出后可以从当前内存文档和标签状态恢复，不依赖自动保存源文件
- [ ] 打开、键入、标签切换、保存和模式切换达到由基准记录并评审的响应门槛
- [ ] 性能日志只记录尺寸、阶段和耗时，不记录笔记正文、搜索词或 Markdown 片段
- [ ] 内存压力下不会提前丢弃脏缓冲区；无法继续时保留恢复快照并给出可操作错误
- [ ] 基准覆盖小文档、长文档、大表格、重数学/Mermaid、嵌入 HTML 和多标签组合
- [ ] 真实 WebKit 自动化覆盖 IME、进程恢复、阈值降级、手动重试、源码往返和内存压力失败
- [ ] App Shell 验证覆盖降级说明、手动尝试、恢复状态、键盘焦点和 VoiceOver 反馈

## Blocked by

- [保真支持完整 Markdown 源码语法](08-preserve-full-markdown-source-syntax.md)
- [交互编辑代码块、表格和任务列表](11-edit-code-tables-and-task-lists.md)
- [安全渲染数学公式、Mermaid、HTML 和远程资源](12-render-math-mermaid-html-and-remote-resources.md)
