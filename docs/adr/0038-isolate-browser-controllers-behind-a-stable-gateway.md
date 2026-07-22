---
status: proposed
---

# 通过稳定网关隔离浏览器控制器

Breath 通过自有、版本化的 `breath browser` CLI/JSON 协议向 Agent 集成暴露浏览器能力。浏览器自动化网关负责校验应用实例、工作会话与 Agent 对话身份，执行权限和 Browser Profile 边界，并提供稳定的会话、页面、观察、操作与错误模型。首个浏览器控制适配器使用 Playwright Library 驱动 Chromium：一个工作会话的浏览器运行时可以在同一个 Chromium 实例中为多个 Agent 对话创建相互隔离的 Browser Context。Playwright 的定位器、对象模型、进程协议和版本细节只是内部实现，不构成 Agent 可依赖的 Breath 接口；Agent 不加载 Playwright MCP 的工具定义，因此其 token 开销由 Breath 的紧凑协议决定。

后续可以在不修改 Agent 集成协议的情况下增加 agent-browser 等适配器，或为非视觉任务增加 Lightpanda 后端，但替代实现必须维持 Agent 对话之间的会话和存储隔离。Breath 不直接向 Agent 暴露第三方 CLI，也不在首版自行实现 CDP 客户端，以换取可控的领域边界和较低的首版实现成本。
