# 打开相对链接并导入笔记附件

Status: implemented

## Parent

[Breath 全局 Markdown 笔记库与笔记 Agent 抽屉](../spec.md)

## What to build

交付 Markdown 资源工作流：用户可以通过 `Cmd` 点击标准相对链接，粘贴或拖入图片及附件，并把富文本转换为干净 Markdown。所有导入资源复制到统一 `_attachments/`，Markdown 继续使用可移植的相对路径。

本切片覆盖 PRD User Stories 47–57、94。

## Acceptance criteria

- [ ] `Cmd` 点击已有库内相对 Markdown 链接会聚焦或打开目标 Note Tab，并定位可解析的标题锚点
- [ ] 链接目标不存在时，无论解析路径位于库内还是库外，都只提示“目标不存在”，不自动创建文件
- [ ] 指向 Note Library 外且真实存在的目标交给 macOS 默认行为打开，不进入 Breath 可编辑标签
- [ ] `[[wikilinks]]` 作为普通源码保留，不提供解析、双链、反向链接或关系图谱
- [ ] 粘贴或拖入图片和普通附件时先复制到 Note Library 根目录 `_attachments/`，成功后才插入相对 Markdown 链接
- [ ] 附件名称冲突使用稳定安全的后缀保留两者，不覆盖未知已有资源
- [ ] 普通 `Cmd-V` 净化富文本或 HTML、转换为干净 Markdown，并把二进制资源交给原生附件服务落盘
- [ ] `Cmd-Shift-V` 只插入纯文本，不执行富文本转换或附件提取
- [ ] 导入失败不插入失效链接，部分批量失败提供逐项结果并保留成功附件
- [ ] 编辑器中的图片保持自然宽高比并受正文宽度约束，不提供拖拽缩放；用户仍可通过安全 HTML 表达尺寸
- [ ] 移动包含附件链接的 Note Document 时沿用链接感知移动契约更新相对路径
- [ ] 删除笔记不会自动删除孤儿附件，页面不提供孤儿附件清理命令
- [ ] 所有文件目标都经过原生层边界验证，WebView 不能自行复制或读取任意外部路径
- [ ] 使用真实临时目录和富文本样本覆盖链接解析、缺失目标、库外目标、冲突附件、粘贴转换、纯文本粘贴和失败回滚
- [ ] App Shell 与真实 WebKit 契约验证 `Cmd` 点击、拖放、粘贴、图片布局、错误反馈、键盘和 VoiceOver 语义

## Blocked by

- [安全重命名和移动文件并改写相对链接](09-rename-move-and-rewrite-links.md)
