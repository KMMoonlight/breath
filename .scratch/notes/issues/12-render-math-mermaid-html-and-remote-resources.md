# 安全渲染数学公式、Mermaid、HTML 和远程资源

Status: implemented

## Parent

[Breath 全局 Markdown 笔记库与笔记 Agent 抽屉](../spec.md)

## What to build

完成复杂 Markdown 的安全渲染路径：支持行内与块级数学公式、Mermaid、受限 HTML 和 HTTPS 远程资源，同时把脚本执行、本地文件访问和网络代理控制留在 Breath 的受信边界。解析或渲染错误只局部降级，不阻止保存或改写用户源码。

本切片覆盖 PRD User Stories 66–68、81–84、93–94。

## Acceptance criteria

- [ ] 行内和块级 LaTeX 使用离线打包的固定版本渲染器显示，源码仍是唯一事实来源
- [ ] Mermaid 使用离线打包的固定版本和严格安全模式渲染，不执行图表中的脚本或任意链接动作
- [ ] 数学或 Mermaid 语法错误显示紧凑的局部错误和可编辑源码，不阻止保存、不自动修复输入
- [ ] Markdown 内安全 HTML 可以保留和展示，脚本、事件处理器、iframe、危险 URL 和其他主动内容被移除或阻止
- [ ] HTML 净化同时应用于文件加载、编辑预览和富文本粘贴，不能通过模式切换绕过
- [ ] WebView 只执行应用打包的受信脚本，不允许 Markdown 注入脚本、导航或任意消息桥调用
- [ ] 本地资源请求先由原生层规范化并验证位于 Note Library，符号链接和目录穿越请求被拒绝
- [ ] Markdown 中的 HTTPS 远程图片和内容通过 Breath 可控网络边界加载，并遵循 Network Proxy、超时和安全错误规则
- [ ] 非 HTTPS、重定向到不允许协议或无法通过代理加载的远程资源显示安静失败，不影响编辑和保存
- [ ] 编辑器中的图片保持自然宽高比并受正文宽度约束，不提供拖拽缩放；安全 HTML 尺寸表达仍可保留
- [ ] 复杂节点未修改时保持原始 Markdown 或 HTML 字节；渲染结果不会写回源文件
- [ ] 固定攻击语料覆盖事件属性、脚本标签、iframe、危险 URL、目录穿越、符号链接和恶意 Mermaid
- [ ] 真实 WebKit 与网络契约验证安全净化、本地边界、代理路由、错误降级、离线依赖和源码往返
- [ ] App Shell 验证覆盖公式、图表、局部错误、远程资源失败、键盘焦点和 VoiceOver 替代描述

## Blocked by

- [保真支持完整 Markdown 源码语法](08-preserve-full-markdown-source-syntax.md)
