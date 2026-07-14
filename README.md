# Breath

Breath 是一个使用 SwiftUI 和 libghostty 构建的 macOS 原生多 Agent 工作台。它以“工作区 → 工作会话 → 终端窗格”组织本地开发工作，终端默认打开空的 login shell，由用户自行启动 Agent CLI。

## v1 能力

- 一个工作区可以包含多个工作会话；工作会话支持递归横向、纵向分屏。
- 关闭主窗口不停止终端；`⌘Q` 确认后保存布局和 Agent session ID，再停止全部进程。
- 冷启动只恢复最后选中的工作会话，其他会话在首次选择时按需恢复。
- 可选用户级集成支持 Codex、Claude Code、Gemini CLI、GitHub Copilot CLI、Qwen Code、Cursor Agent、Factory Droid、OpenCode 和 Pi。
- Agent 状态来自官方 hooks/plugin，不解析终端输出，也不保存提示词、回复、工具内容或 transcript。
- 应用配置与终端配置相互独立；终端配置不读取或导入 Ghostty 配置。

## 本地构建

要求 macOS 14+、Xcode/Swift 6.2、Zig 0.15 和 Apple Metal Toolchain。

```sh
scripts/build-libghostty.sh
swift test
swift run Breath
```

`Vendor/GhosttyKit.xcframework` 是固定 Ghostty revision 生成的本地产物，不提交到 Git。没有该产物时项目仍可编译，但终端区域只显示构建提示。

发布与签名流程见 [docs/releasing.md](docs/releasing.md)，产品范围和架构见 [docs/design/v1-product-and-architecture.md](docs/design/v1-product-and-architecture.md)。
