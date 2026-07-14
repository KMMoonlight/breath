# Breath

Breath 是一个面向本地软件项目的 macOS 多 Agent 工作台，用于组织和观察多个 Agent CLI 的并行工作。

## Language

**Agent 工作台（Agent Workbench）**：
以多个 Agent 的组织、并行运行和状态观察为核心的桌面应用；终端是工作会话的交互界面，而不是产品本身。
_Avoid_: 多窗格终端、终端复用器、通用终端

**工作区（Workspace）**：
用户添加到工作台中的一个本地项目目录，是组织工作会话的边界；一个工作区可以包含多个工作会话。规范化后的同一本地目录在工作台中只能对应一个工作区；目录不可用时，工作台保留记录并提示用户移除，不自动删除或重新定位。用户确认移除后，Breath 停止相关终端并删除该工作区的本地元数据，但不修改项目目录或其中的文件。
_Avoid_: 仓库、项目窗口

**工作会话（Work Session）**：
工作区内一项可持续恢复的工作，拥有自己的终端布局；一个工作区可以包含多个工作会话。正常退出后重新启动 Breath 时，只有退出前选中的工作会话会立即实例化其终端窗格并尝试恢复 Agent 对话；其他工作会话只恢复到会话树中，在用户切换选中时才实例化和恢复。工作会话一旦实例化，切换到其他会话不会暂停或终止其中的 Shell 和 Agent。如果退出前选中的工作会话已归档、已删除或所属工作区不可用，Breath 不自动改选其他会话，也不创建终端。
_Avoid_: 对话窗口、终端窗口、Agent 会话

**归档工作会话（Archived Work Session）**：
由用户明确点击归档后从活跃会话树中移出的工作会话。归档会停止其中所有终端进程，但保留布局和可恢复的 Agent 对话信息；如果存在正在执行的 Agent 回合或其他前台进程，停止前需要二次确认。归档项不出现在左侧会话树，只能在设置窗口的“已归档”管理页面查看；该页面不是应用配置或终端配置。恢复只撤销归档并把原工作会话重新加入左侧会话列表，保持设置窗口与当前选择不变，也不立即创建进程；用户之后选中它时，曾运行 Agent CLI 且具有可用会话标识的终端窗格才自动恢复 Agent 对话，其他窗格只恢复布局。永久删除归档需要二次确认，只删除 Breath 元数据，不删除项目文件或 Agent CLI 自身保存的对话。Agent 回合完成不会自动归档工作会话。
_Avoid_: 已完成回合、已删除会话、自动归档会话

**终端窗格（Terminal Pane）**：
工作会话终端布局中的一个独立交互区域。新建工作会话或执行分屏时，新的终端窗格均从工作区目录中的空 Shell 开始；多个窗格只共享布局，不继承彼此的目录、进程或 Agent 对话。一个窗格最多绑定一个可恢复的 Agent 对话，并以最近启动的受支持 Agent 对话替换旧绑定；旧对话仍由原 Agent CLI 保管，但 Breath 不再自动恢复它。多窗格时可单独关闭并停止自身进程，最后一个窗格不能单独关闭，只能通过归档结束整个工作会话。
_Avoid_: 分离窗口、对话窗口

**终端状态（Terminal State）**：
终端窗格当前的 Agent 活动状态，只取“空闲、运行中、需要处理、回合完成”之一。普通 Shell、Agent 已退出和恢复失败都属于空闲；Agent 类型是否已识别作为独立信息展示。状态变化只呈现在会话树中，不触发系统通知。
_Avoid_: 进程状态、会话状态、已退出状态

**分屏（Split）**：
把当前终端窗格沿横向或纵向划分，并创建一个独立终端窗格的操作；任意窗格都可以继续分屏，形成递归布局。新分屏默认等分，用户调整后的递归布局和各层比例会随工作会话持久化。
_Avoid_: 分离窗口、复制终端、继承终端

**会话树（Session Tree）**：
侧栏中按照“工作区 → 工作会话 → 终端窗格”组织内容的层级导航。工作会话只有一个终端窗格时不显示窗格层级，并直接承载该窗格的状态；产生分屏后才展示第三级，状态只显示在各终端窗格节点上，不汇总到父节点。
_Avoid_: 文件夹列表、对话列表、标签栏

**终端配置（Terminal Settings）**：
由 Breath 拥有、只负责终端内部样式的配置，例如字体、字号、颜色主题和光标样式。
_Avoid_: Ghostty 配置、Shell 配置、终端行为配置、终端样式配置

**应用配置（Application Settings）**：
由 Breath 拥有、只负责终端之外应用界面样式的配置。
_Avoid_: 终端配置、应用行为配置、Agent 项目配置

**应用更新（Application Update）**：
Breath 通过 Sparkle 在应用内完成的版本检查、签名验证和安装流程。构建产物与更新包由公开 GitHub Releases 托管，签名后的 appcast 由同一 GitHub 仓库的 GitHub Pages 托管；客户端不使用自建更新服务、GitHub 登录或访问令牌。
_Avoid_: Breath 更新服务器、GitHub API 更新器、静默强制更新

**Agent CLI**：
用户在终端窗格中手动启动、并通过终端持续交互的编码 Agent 命令行程序。
_Avoid_: 内置 Agent、Agent 配置、Agent 实例

**Agent 对话（Agent Conversation）**：
由 Agent CLI 自身拥有、可以在原进程结束后续接的交互上下文。它通过 Agent CLI 分配的原生会话标识绑定到 Breath 的一个终端窗格。
_Avoid_: 工作会话、终端会话、终端进程

**Agent 原生标题（Agent Native Title）**：
由 Agent CLI 根据自身对话生成并通过官方接口暴露的标题或摘要，Breath 可以将其用于会话树命名，但不会读取原始对话或调用额外模型生成标题。工作会话获得的第一个原生标题成为父级名称，各终端窗格显示各自 Agent 的原生标题；这些名称不支持手动修改。获得标题前，父级显示带创建时间的“新会话”，窗格显示“终端 N”，始终无法获得标题时保留占位名称。
_Avoid_: Breath 生成标题、首条提示词、终端输出标题

**Agent 回合（Agent Turn）**：
Agent 对话中的一次工作周期，从 Agent 接受用户指令并开始处理，到完成当前工作并重新等待用户输入为止。
_Avoid_: Agent 进程、工作会话、Agent 对话

**回合完成（Turn Completed）**：
Agent 已完成当前回合并等待下一条用户指令的状态；它不表示 Agent CLI 进程已经退出。
_Avoid_: 进程结束、会话结束、任务关闭

**Agent 会话标识（Agent Session ID）**：
Agent CLI 为可恢复的 Agent 对话分配的原生标识，由对应的 Agent 适配器捕获并用于后续恢复。
_Avoid_: 工作会话 ID、终端 ID、进程 ID

**Agent 适配器（Agent Adapter）**：
为特定 Agent CLI 提供状态识别、会话标识捕获和对话恢复等增强能力的可选扩展；没有对应适配器的 CLI 仍可作为普通终端程序运行。
_Avoid_: Agent 后端、Agent 驱动、内置 Agent

**Agent 集成（Agent Integration）**：
用户明确启用、安装在个人环境中并可完整移除的 Agent CLI 生命周期连接。它把 Agent 事件交给对应适配器，但不修改项目目录中的 Agent 配置。
_Avoid_: Agent 适配器、项目 Hook、自动注入

**Agent 事件（Agent Event）**：
Agent 集成在生命周期节点产生、并关联到具体终端窗格的状态消息，用于更新 Agent 回合状态，或捕获原生会话标识和 Agent 原生标题。
_Avoid_: 终端输出、进程状态、Agent 消息内容

**受支持 Agent CLI（Supported Agent CLI）**：
拥有官方本地生命周期扩展机制，并由 Breath 内置适配器及兼容性测试覆盖的 Agent CLI。首版支持矩阵包含 Codex、Claude Code、Gemini CLI、GitHub Copilot CLI、Qwen Code、Cursor Agent、Factory Droid、OpenCode 和 Pi。
_Avoid_: 任意 Agent CLI、所有带 hooks 的 CLI、普通终端程序
