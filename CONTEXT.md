# Breath

Breath 是一个面向本地软件项目的 macOS 多 Agent 工作台，用于组织和观察多个 Agent CLI 的并行工作。

## Language

**Agent 工作台（Agent Workbench）**：
以多个 Agent 的组织、并行运行和状态观察为核心的桌面应用；终端是工作会话的交互界面，而不是产品本身。
_Avoid_: 多窗格终端、终端复用器、通用终端

**工作区（Workspace）**：
用户添加到工作台中的一个本地项目目录，是组织工作会话的边界；一个工作区可以包含多个工作会话。规范化后的同一本地目录在工作台中只能对应一个工作区；目录不可用时，工作台保留记录并提示用户移除，不自动删除或重新定位。用户确认移除后，Breath 停止相关终端并删除该工作区的本地元数据，但不修改项目目录或其中的文件。
_Avoid_: 仓库、项目窗口

**Git 工作台（Git Workbench）**：
Breath 内嵌、以用户在 Git 页面选择的工作区中的 Git 仓库为操作对象的通用图形化 Git 工具。入口始终位于左侧活动栏；打开时默认使用当前选中工作会话所属的工作区，没有选中工作区时仍可进入页面，目录选择器显示“请选择”。除此之外，它独立于终端窗格和 Agent 生命周期，不根据 Agent 上下文改变行为。
_Avoid_: Agent Git、会话 Git、Git Diff 查看器

**活动栏（Activity Bar）**：
主窗口最左侧固定的图标导航，按“工作区、任务、Git、Skills、设置”排列。只有选择“工作区”时才展示会话树与终端分栏；选择其他入口时隐藏会话树，并让对应页面占满活动栏右侧区域。
_Avoid_: 侧栏底栏、状态栏、工具栏

**Git Root**：
工作区内由 Git 独立管理的一个仓库根目录。一个工作区可以包含多个 Git Root；Git 工作台既可以聚合展示全部 Git Root，也可以聚焦操作其中一个。
_Avoid_: 子工作区、模块仓库、项目仓库

**变更列表（Changelist）**：
Git 工作台默认使用的本地变更组织单元，用于把尚未提交的文件、Hunk 或行分组为彼此独立的提交候选；它是 Breath 保存的工作区元数据，不等同于 Git Index。
_Avoid_: 暂存区、Commit、任务

**Git 暂存区（Git Staging Area）**：
Git 工作台可选使用的原生 Git Index 工作模式，将本地变更明确区分为未暂存和已暂存。启用时暂时隐藏变更列表工作流，但保留已有变更列表元数据，以便切回时恢复。
_Avoid_: 变更列表、提交队列、选中文件

**Git 安全快照（Git Safety Snapshot）**：
Git 工作台在执行可能覆盖或丢弃本地内容的操作前保存的本机恢复点。它只覆盖由 Breath 发起的高风险 Git 操作，不是对终端、Agent 或其他应用产生的全部文件变化进行持续记录的完整 Local History。
_Avoid_: Local History、自动提交、Git Stash、备份仓库

**Git Stash**：
由 Git 创建和管理的临时变更记录，可以被终端、Breath 或其他 Git 工具共同查看和应用。
_Avoid_: Shelf、Git 安全快照、草稿 Commit

**Shelf**：
由 Breath 在本机保存的可重复应用补丁集合，可以只包含选中的文件或变更列表，不写入 Git 仓库。
_Avoid_: Git Stash、Git 安全快照、变更列表

**工作会话（Work Session）**：
工作区内一项可持续恢复的工作，拥有自己的终端布局；一个工作区可以包含多个工作会话。同一工作区的活跃工作会话同时显示在终端区域顶部的工作会话标签栏中，选中的工作会话作为当前 Tab 内容展示自己的完整分屏布局。每个工作会话只在一个会话工作目录中运行；同一会话内的全部终端窗格共享该目录。正常退出后重新启动 Breath 时，只有退出前选中的工作会话会立即实例化其终端窗格并尝试恢复 Agent 对话；其他工作会话只恢复到会话树和标签栏中，在用户切换选中时才实例化和恢复。工作会话一旦实例化，切换到其他会话不会暂停或终止其中的 Shell 和 Agent。如果退出前选中的工作会话已归档、已删除或所属工作区不可用，Breath 不自动改选其他会话，也不创建终端。
_Avoid_: 对话窗口、终端窗口、Agent 会话

**会话工作目录（Session Working Directory）**：
一个工作会话及其全部终端窗格共同使用的代码目录，只能是工作区的本地检出或该会话专属的托管工作树。
_Avoid_: 窗格工作目录、Agent 工作目录、当前目录

**托管工作树（Managed Worktree）**：
Breath 为一个工作会话创建和管理的独立 Git 检出；它与工作区的本地检出共享仓库历史，但拥有独立文件状态，并且不与其他工作会话共用。Breath 只保存定位、基线、仓库关联和生命周期所需的元数据，不保存其中的 diff、文件名列表或提交消息。
_Avoid_: Agent 工作树、工作树工作区、仓库副本

**不可用工作树（Unavailable Worktree）**：
记录仍属于工作树会话、但目录缺失或 Git 工作树元数据已无法使用的托管工作树。Breath 不自动重建它，也不为所属会话启动终端。
_Avoid_: 空工作树、已删除会话、自动恢复工作树

**本地会话（Local Session）**：
以工作区的本地检出作为会话工作目录的工作会话，是普通“新建工作会话”操作创建的默认类型。
_Avoid_: 普通会话、默认会话、非工作树会话

**工作树会话（Worktree Session）**：
以自身专属的托管工作树作为会话工作目录的工作会话，只能由用户在工作区菜单中明确选择创建；归档期间仍保留同一个托管工作树。它的运行可用性取决于该托管工作树自身是否仍是有效的 Git 工作树，不直接继承本地检出的目录可用状态。
_Avoid_: Agent 工作树、工作树工作区、隔离会话

**导出为分支（Export as Branch）**：
为工作树会话操作当时的 `HEAD` 创建一个新的 Git 分支引用；这是一次性提交快照，工作树保持 detached HEAD，之后产生的提交不会自动推进已经导出的分支，操作时存在的未提交修改也不属于该分支。
_Avoid_: 保留为分支、绑定分支、同步分支

**归档工作会话（Archived Work Session）**：
由用户明确点击归档后从活跃会话树中移出的工作会话。归档会停止其中所有终端进程，但保留布局、会话工作目录和可恢复的 Agent 对话信息；如果存在正在执行的 Agent 回合或其他前台进程，停止前需要二次确认。归档项不出现在左侧会话树，只能在主窗口右侧设置页面的“已归档”管理页查看；该页面不是应用配置或终端配置。恢复只撤销归档并把原工作会话重新加入左侧会话列表，保持设置页面与当前工作会话选择不变，也不立即创建进程；用户之后选中它时，曾运行 Agent CLI 且具有可用会话标识的终端窗格才自动恢复 Agent 对话，其他窗格只恢复布局。永久删除本地会话只删除 Breath 元数据；永久删除工作树会话还会删除其托管工作树，存在未提交修改或未受本地分支、标签保护的新增提交时必须单独进行高风险确认。两种删除都不移除 Agent CLI 自身保存的对话。Agent 回合完成不会自动归档工作会话。
_Avoid_: 已完成回合、已删除会话、自动归档会话

**终端窗格（Terminal Pane）**：
工作会话终端布局中的一个独立交互区域。新建工作会话或执行分屏时，新的终端窗格均从会话工作目录中的空 Shell 开始；多个窗格共享会话工作目录和布局，但不继承彼此的进程、环境增量或 Agent 对话。一个窗格最多绑定一个可恢复的 Agent 对话，并以最近启动的受支持 Agent 对话替换旧绑定；旧对话仍由原 Agent CLI 保管，但 Breath 不再自动恢复它。多窗格时可单独关闭并停止自身进程，最后一个窗格不能单独关闭，只能通过归档结束整个工作会话。
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

**工作会话标签栏（Work Session Tab Bar）**：
终端区域顶部的浏览器式导航，列出当前选中工作区内的全部活跃工作会话。选择 Tab 只切换其工作会话内容，不改变或重组会话内的递归分屏；新增按钮创建并选中新工作会话，关闭按钮沿用归档语义。标签栏横向空间不足时滚动，不把会话折叠进隐式的“更多”菜单。尚未获得 Agent 原生标题的 Tab 只显示“新会话”，不显示创建时间；当前选中的前九个 Tab 显式显示对应的 `⌘1` 至 `⌘9` 提示，这些快捷键分别切换到同一工作区的第 1 至第 9 个 Tab。
_Avoid_: 终端标签、分屏标签、窗口标签

**终端配置（Terminal Settings）**：
由 Breath 拥有、只负责终端内部样式的配置，例如字体、字号、颜色主题和光标样式。
_Avoid_: Ghostty 配置、Shell 配置、终端行为配置、终端样式配置

**快捷键优先级（Shortcut Priority）**：
当前输入焦点位于终端窗格时，可能与 Breath 自有快捷键冲突的按键先交给窗格内运行的 Shell、Agent CLI 或其他 TUI；当窗格内应用启用了可表示该组合键的终端键盘协议，且按键成功送入子进程时视为已处理，否则同一个按键继续交给 Breath。Ghostty 自身的窗口、Tab、分屏等宿主级动作不属于此优先级，Breath 在生成的内部 Ghostty 配置中取消与自身快捷键冲突的内建绑定。输入焦点不在终端时由 Breath 直接处理，窗格级动作指向最后聚焦的终端窗格。`⌘[` 和 `⌘]` 分别循环聚焦当前工作会话中的上一个和下一个分屏。macOS 系统生命周期快捷键不属于此规则。
_Avoid_: 快捷键冲突、终端快捷键配置、Agent 快捷键配置

**应用配置（Application Settings）**：
由 Breath 拥有、只负责终端之外应用界面样式的配置。
_Avoid_: 终端配置、应用行为配置、Agent 项目配置

**应用更新（Application Update）**：
Breath 通过 Sparkle 在应用内完成的版本检查、签名验证和安装流程。构建产物与更新包由公开 GitHub Releases 托管，签名后的 appcast 由同一 GitHub 仓库的 GitHub Pages 托管；客户端不使用自建更新服务、GitHub 登录或访问令牌。
_Avoid_: Breath 更新服务器、GitHub API 更新器、静默强制更新

**Agent CLI**：
用户在终端窗格中手动启动、并通过终端持续交互的编码 Agent 命令行程序。
_Avoid_: 内置 Agent、Agent 配置、Agent 实例

**全局 Skill（Global Skill）**：
不属于任何工作区、可在当前 macOS 用户的所有项目中使用的 Agent 能力说明；同一个全局 Skill 可以面向一个或多个 Agent CLI。它是否属于全局 Skill，不取决于由 Breath、Agent CLI 还是其他工具完成安装；名称相同但内容不同的能力说明属于不同的全局 Skill，但同一个 Agent CLI 中只能安装其中一个，后安装项必须由用户明确选择覆盖或跳过。
_Avoid_: 项目 Skill、Agent 集成、工作区 Skill

**Skill 安装目标（Skill Installation Target）**：
用户为一次全局 Skill 安装明确选择、已安装在当前设备上且能可靠解析全局 Skill 目录的受支持 Agent CLI；只有被选择的 Agent CLI 才获得该 Skill。Skill 安装目标与受支持 Agent CLI 使用同一支持矩阵，新增受支持 Agent CLI 时同步纳入候选范围；尚未安装或目录无法确认的 Agent CLI 只显示状态，不能成为安装目标。
_Avoid_: 默认 Agent、受支持 Agent CLI、自动分发目标

**Skill 来源（Skill Source）**：
用户用来发现待安装 Skill 的 ZIP 文件、GitHub Repo 或 skills.sh 条目；一个来源可以包含一个或多个候选 Skill，来源本身不等同于全局 Skill。
_Avoid_: 全局 Skill、Skill 安装目标、Agent 仓库

**Skill 来源身份（Skill Source Identity）**：
安装预览用来确认候选 Skill 与既有副本是否来自同一远程条目的稳定标识；skills.sh 使用目录条目 ID，GitHub 使用仓库与来源内相对路径。它不作为 Skills 浏览列表信息，缺失时只能退化为同名或内容比较。
_Avoid_: Skill 名称、作者、Skill 来源、内容摘要

**候选 Skill（Skill Candidate）**：
从 Skill 来源中发现、尚未写入 Agent 目录的 Skill；缺少可解析的 `SKILL.md`、`name` 或 `description` 时不能安装，非致命的格式偏差可以带警告进入安装预览。
_Avoid_: 全局 Skill、无效文件夹、已安装 Skill

**无法识别的 Skill 项目（Unrecognized Skill Item）**：
位于 Agent Skill 目录中、但无法解析成全局 Skill 的文件夹或链接；Breath 在扫描结果中保留其诊断信息，但不在 Skills 页面展示、不计入 Skill 列表，也不直接删除或修改。
_Avoid_: 全局 Skill、候选 Skill、来源未知 Skill

**Skill 上游（Skill Upstream）**：
与已安装全局 Skill 关联、且可由安装记录或兼容清单确认的 GitHub Repo 或 skills.sh 远程位置，是检查和获取更新的依据；Breath 不根据名称猜测上游，ZIP 来源和来源未知的 Skill 都没有 Skill 上游。
_Avoid_: Skill 来源、ZIP 文件、Agent 目录

**Skill 安装记录（Skill Installation Record）**：
Breath 在本机保存、用于把一个 Agent 目录中的全局 Skill 副本关联到来源、可选上游版本和安装时内容的记录；ZIP 记录只有来源分类，远程记录才包含 Skill 上游。它不决定 Skill 是否已安装，记录丢失只会使来源与更新能力不可确认。
_Avoid_: 全局 Skill、副本目录、安装清单文件

**Skill 安装预览（Skill Installation Review）**：
全局 Skill 写入 Agent 目录前必须经过的用户确认，呈现来源、说明、文件、安装目标和将被替换的既有内容；检查预览内容不执行其中的脚本。
_Avoid_: 搜索结果、安装结果、脚本试运行

**Skill 安全审计（Skill Security Audit）**：
skills.sh 等来源对候选 Skill 提供的辅助风险报告，不构成安全保证，也不能替代 Skill 安装预览；未知状态不表示安全，高风险结果要求额外确认但不永久禁止安装。
_Avoid_: 安全认证、安装许可、内容预览

**Skill 更新（Skill Update）**：
从已确认的 Skill 上游取得新内容并替换已安装副本的用户操作；Breath 可以自动检查更新，但只有用户完成内容预览并确认后才写入，失败时保留原版本。
_Avoid_: 自动同步、重新安装、后台覆盖

**本地修改 Skill（Locally Modified Skill）**：
实际内容与 Skill 安装记录中的内容摘要不同、但路径与身份仍能确认的远程来源全局 Skill；它保留 Skill 上游，更新前必须明确展示将被替换的本地修改。
_Avoid_: 来源未知 Skill、可用更新、同名 Skill

**Skill 卸载（Skill Uninstall）**：
从用户明确选择的一个或多个 Skill 安装目标中移除全局 Skill 副本的操作；各目标独立产生结果，不删除 Skill 来源，也不影响未选择的 Agent。普通目录移入 macOS 废纸篓以便恢复，符号链接只移除链接。
_Avoid_: 删除来源、全局清理、移除 Agent

**Skill 安装结果（Skill Installation Result）**：
一个候选 Skill 写入一个 Skill 安装目标的独立结果；批量安装可以部分成功，某个结果失败不回滚其他成功结果，但失败目标不能留下不完整的 Skill 目录。
_Avoid_: 整批安装事务、部分目录、统一失败

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
