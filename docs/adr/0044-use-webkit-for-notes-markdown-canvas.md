# 仅在 Notes Markdown 画布中使用 WebKit

Breath 的 Activity Bar、文件树、Note Tab Bar、搜索、设置、对话框和抽屉布局继续使用 SwiftUI 或 AppKit，原生终端继续使用 Ghostty/AppKit。为了在同一画布中交付 Typora 风格编辑、完整 Markdown 扩展、受限 HTML、数学公式和 Mermaid，Notes 的 Markdown 编辑画布可以使用一个由全部 Note Tab 共享的 `WKWebView`，其中只运行固定版本、随应用离线发布的 Tiptap Core 与 Breath 源码保真层。该 WebView 只能访问应用资源和经原生层验证的 Note Library 资源，远程请求必须经过 Breath 网络边界。

这项决定只替代 ADR 0006 中“整个产品不使用 WebView”的绝对限制，不改变其原生应用外壳和专用原生终端方向。Markdown 源文件仍是唯一事实来源；WebView 是可替换的编辑视图，不拥有文件、标签、保存、恢复或 Agent 生命周期。
