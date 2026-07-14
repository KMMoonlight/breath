# 站外发行且不启用 App Sandbox

Breath 首版不通过 Mac App Store 发行，而是使用 Developer ID 签名和 Apple 公证进行站外分发，并且不启用 App Sandbox。内置终端及其启动的 Agent CLI 需要访问用户选择的项目之外的 Shell 配置、开发工具链和 Agent 配置；Mac App Store 强制要求的沙箱会让这种行为与用户在系统终端中的环境产生明显差异。
