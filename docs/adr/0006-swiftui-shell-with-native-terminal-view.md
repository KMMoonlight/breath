# SwiftUI 应用外壳与专用原生终端视图

Breath 的应用外壳、侧栏、设置和窗口管理使用 SwiftUI，终端区域则允许使用 AppKit 或 Metal 实现，并通过 `NSViewRepresentable` 嵌入。终端的高频文本渲染、键盘与输入法处理、选区和滚动有专门性能需求，不要求纯 SwiftUI 实现，但整个产品仍保持 macOS 原生技术栈且不使用 WebView 或 Electron。
