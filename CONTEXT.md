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
Breath 内嵌、以用户在 Git 页面选择的工作区中的 Git 仓库为操作对象的通用图形化 Git 工具。入口始终位于左侧活动栏；打开时默认使用当前选中工作会话所属的工作区，没有选中工作区时仍可进入页面，目录选择器显示“请选择”。除此之外，它独立于终端窗格和 Agent 生命周期，不根据 Agent 上下文改变行为。分支导航将本地分支与远程跟踪分支分组展示，本地分支作为默认可见的主列表，远程分支默认收起；远端默认分支的 `HEAD` 符号引用不作为可选择分支展示。单击分支行只选择该分支，双击或显式使用 `Checkout` 操作才切换分支。若本地修改会被切换覆盖，Git 工作台提供 Smart Checkout、Force Checkout 和取消：Smart Checkout 通过临时 Git Stash 保留并恢复修改，Force Checkout 明确丢弃修改，但两者执行前都创建 Git 安全快照。
_Avoid_: Agent Git、会话 Git、Git Diff 查看器

**活动栏（Activity Bar）**：
主窗口最左侧固定的图标导航；“工作区、任务、Git、Skills、额度”从顶部依次排列，“设置”固定在活动栏底部。只有选择“工作区”时才展示会话树与终端分栏；选择其他入口时隐藏会话树，并让对应页面占满活动栏右侧区域。
_Avoid_: 侧栏底栏、状态栏、工具栏

**任务（Task）**：
用户创建、属于一个工作区并可由 Breath 启动执行的工作项，包含任务描述、实现 Agent、验收目标以及 Git 工作区中使用的任务分支；其主状态只取“待办、进行中、评审、完成”之一。“完成”表示任务执行和评审已经结束，不表示任务分支已经合并到其他分支。
_Avoid_: 工作会话、Agent 回合、变更列表

**任务分支（Task Branch）**：
Git 任务执行期间由托管工作树检出、承载该任务代码成果的本地分支，例如 `task/123`；它由用户为任务指定，其后续合并由用户在任务流程之外自行处理。
_Avoid_: 合并目标分支、基线分支、Worktree 分支

**起始分支（Start Branch）**：
用户创建工作树会话时选择、只用于确定新会话分支初始提交的本地分支或远程跟踪分支；默认选择工作区当前分支。起始分支不会被新工作树直接检出，因此可以继续由原工作区或其他 Worktree 使用。
_Avoid_: 会话分支、任务分支、合并目标分支

**会话分支（Session Branch）**：
Breath 为用户显式创建的每个工作树会话自动创建、由该会话独占检出的本地分支，名称为 `breath/<work-session-id>`。它从用户选择的起始分支当前提交开始，承载该会话的后续代码成果；删除托管工作树时保留会话分支。
_Avoid_: 起始分支、任务分支、当前分支

**任务执行（Task Execution）**：
用户启动任务后形成的一次可持续恢复的执行，关联该任务使用的工作会话、实现 Agent 和代码目录；同一次执行在“进行中”和“评审”之间往返时继续使用原有工作会话和代码成果。
_Avoid_: Agent 回合、终端进程、任务状态

**验收目标（Acceptance Goal）**：
用户为任务定义、用于判断实现是否达到预期的可观察条件，是实现 Agent 和任务评审共同使用的完成标准。
_Avoid_: Agent 提示词、测试命令、评审意见

**任务评审（Task Review）**：
任务执行从“进行中”提交到“评审”后，针对固定代码结果和验收目标进行的一次检查；评审只产生“通过”或“需要修改”的结论，不直接等同于 Agent 回合完成。
_Avoid_: Git 工作台、代码浏览、任务完成

**评审意见（Review Finding）**：
任务评审发现、需要实现 Agent 继续处理的具体问题；任务返回“进行中”时，Breath 将本轮评审意见作为后续指令发送到原任务执行。
_Avoid_: 验收目标、Git Diff 评论、用户提示词

**浏览器自动化会话（Browser Automation Session）**：
Agent 对话拥有的、由 Agent 驱动并由用户监督的隔离网页操作上下文；一个 Agent 对话至多拥有一个浏览器自动化会话，会话可以包含多个浏览器页面。同一工作会话中的多个 Agent 对话可以并行拥有各自会话，但它不是供用户日常浏览的内置浏览器。
_Avoid_: 内置浏览器、浏览器 Tab、Computer Use 会话

**浏览器页面（Browser Page）**：
浏览器自动化会话中具有稳定身份的单个网页操作目标；一个 Agent 可以拥有多个页面，但不能引用其他 Agent 对话的页面。
_Avoid_: 浏览器窗口、顶层浏览器会话、WebView

**浏览器配置档案（Browser Profile）**：
Agent 对话拥有的隔离浏览器身份，包含其浏览器自动化会话使用的 Cookie、Local Storage 和登录状态；它可以跨运行时恢复，但不与其他 Agent 对话共享，并随 Agent 对话或其工作会话永久删除。
_Avoid_: 工作区浏览器状态、工作会话共享 Profile、用户默认浏览器 Profile

**浏览器运行时（Browser Runtime）**：
工作会话按需启动并管理的浏览器控制进程集合；首版使用一个 Chromium 实例承载该工作会话内多个 Agent 对话相互隔离的 Browser Context。它是可替换的基础设施，不是 Agent 或用户直接操作的浏览器会话。
_Avoid_: 浏览器自动化会话、内置浏览器、Agent 浏览器进程

**浏览器集成（Browser Integration）**：
用户为某个 Agent CLI 显式启用的可逆集成，使 Agent 可以发现当前工作会话的浏览器自动化会话；它只在 Breath 环境标识和本地实例握手同时有效时激活，在普通终端中保持休眠。
_Avoid_: 默认浏览器 Hook、全局浏览器注入、Prompt 监听

**浏览器自动化网关（Browser Automation Gateway）**：
Breath 向浏览器集成提供的稳定、版本化 CLI/JSON 协议；它验证当前应用实例、工作会话和 Agent 对话身份，执行权限与配置档案边界，并把操作转交给可替换的浏览器控制适配器。Agent 不直接依赖第三方控制器的命令或会话模型。
_Avoid_: agent-browser 命令包装、Playwright API、浏览器 MCP

**浏览器控制适配器（Browser Controller Adapter）**：
浏览器自动化网关内部把 Breath 的会话、页面、观察、操作和错误模型映射到具体自动化控制器的实现；首个适配器使用 Playwright Library 驱动 Chromium，但 Playwright 及其定位器和对象模型不属于 Breath 的公开协议。
_Avoid_: 浏览器自动化网关、Agent 工具、固定浏览器后端

**浏览器结构化快照（Browser Structured Snapshot）**：
浏览器页面在某一时刻的可访问性结构、稳定元素引用、URL 和标题，是 Agent 观察页面和定位交互目标的默认数据；它不是原始 DOM，也不证明页面视觉呈现正确。
_Avoid_: 页面截图、HTML 转储、视觉验证

**浏览器视觉验证（Browser Visual Verification）**：
使用具备图形渲染能力的浏览器引擎生成页面截图，并据此检查布局、样式或视觉缺陷的验证步骤；首版必须由 Chromium 完成，Lightpanda 的结构化结果不能标记为视觉验证。
_Avoid_: 结构化快照、每步截图、无头抓取

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
Breath 为一个工作会话创建和管理、绑定一个会话分支或任务分支的独立 Git 检出；它与工作区的本地检出共享仓库历史，但拥有独立文件状态，并且不与其他工作会话共用。删除托管工作树不删除其绑定分支。
_Avoid_: Agent 工作树、工作树工作区、仓库副本

**不可用工作树（Unavailable Worktree）**：
记录仍属于工作树会话、但目录缺失或 Git 工作树元数据已无法使用的托管工作树。Breath 不自动重建它，也不为所属会话启动终端。
_Avoid_: 空工作树、已删除会话、自动恢复工作树

**本地会话（Local Session）**：
以工作区的本地检出作为会话工作目录的工作会话，是普通“新建工作会话”操作创建的默认类型。
_Avoid_: 普通会话、默认会话、非工作树会话

**工作树会话（Worktree Session）**：
以自身专属的托管工作树作为会话工作目录、并持续在同一会话分支或任务分支上工作的工作会话，可以由用户明确创建，也可以在用户启动 Git 任务时由 Breath 自动创建；归档期间仍保留同一个托管工作树。
_Avoid_: Agent 工作树、工作树工作区、隔离会话

**归档工作会话（Archived Work Session）**：
由用户明确点击归档后从活跃会话树中移出的工作会话。归档操作不需要二次确认，会停止其中所有终端进程，但保留布局、会话工作目录和可恢复的 Agent 对话信息。归档项不出现在左侧会话树，只能在主窗口右侧设置页面的“已归档”管理页查看；该页面不是应用配置或终端配置。恢复只撤销归档并把原工作会话重新加入左侧会话列表，保持设置页面与当前工作会话选择不变，也不立即创建进程；用户之后选中它时，曾运行 Agent CLI 且具有可用会话标识的终端窗格才自动恢复 Agent 对话，其他窗格只恢复布局。永久删除本地会话只删除 Breath 元数据；永久删除工作树会话还会删除其托管工作树并保留绑定分支，存在未提交修改、未受本地分支或标签保护的提交、Worktree 锁定或状态不可验证时拒绝删除。两种删除都不移除 Agent CLI 自身保存的对话。Agent 回合完成不会自动归档工作会话。
_Avoid_: 已完成回合、已删除会话、自动归档会话

**终端窗格（Terminal Pane）**：
工作会话终端布局中的一个独立交互区域。新建工作会话或执行分屏时，新的终端窗格均从会话工作目录中的空 Shell 开始；多个窗格共享会话工作目录和布局，但不继承彼此的进程、环境增量或 Agent 对话。一个窗格最多绑定一个可恢复的 Agent 对话，并以最近启动的受支持 Agent 对话替换旧绑定；旧对话仍由原 Agent CLI 保管，但 Breath 不再自动恢复它。多窗格时可单独关闭并停止自身进程；最后一个窗格不能单独关闭，此时 `⌘W` 沿用工作会话 Tab 的关闭语义，直接归档整个工作会话，而不是关闭 Breath 主窗口。
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
终端区域顶部的浏览器式导航，列出当前选中工作区内的全部活跃工作会话。选择 Tab 只切换其工作会话内容，不改变或重组会话内的递归分屏；新增按钮紧跟在最后一个 Tab 右侧并与 Tab 一起横向滚动，创建后选中新工作会话；编辑器入口固定在标签栏最右侧；关闭按钮沿用归档语义。标签栏横向空间不足时滚动，不把会话折叠进隐式的“更多”菜单。尚未获得 Agent 原生标题的 Tab 只显示“新会话”，不显示创建时间；前九个 Tab 始终显式显示对应的 `⌘1` 至 `⌘9` 提示，这些快捷键分别切换到同一工作区的第 1 至第 9 个 Tab。
_Avoid_: 终端标签、分屏标签、窗口标签

**终端配置（Terminal Settings）**：
由 Breath 拥有、只负责终端内部样式的配置，例如字体、字号、颜色主题和光标样式。
_Avoid_: Ghostty 配置、Shell 配置、终端行为配置、终端样式配置

**快捷键优先级（Shortcut Priority）**：
当前输入焦点位于终端窗格时，Breath 按用户选择的所有权策略仲裁已注册的宿主快捷键；未注册的按键始终交给窗格内运行的 Shell、Agent CLI 或其他 TUI，例如 `Shift+Tab` 由 Claude Code 等终端内应用处理。“Breath 优先”是默认策略，已注册的应用级快捷键由 Breath 处理，例如 `⌘T` 新建工作会话；“终端优先”把这些应用级快捷键交给终端内应用，Breath 不根据子进程是否产生可见响应再次回退。终端级 Breath 快捷键在两种策略下均由 Breath 处理，包括 `⌘[`、`⌘]`、`⌘D`、`⌘⇧D` 和 `⌘W`。终端键盘协议能够编码某个组合键不代表子进程为它注册了动作；Ghostty 自身的窗口、Tab、分屏等宿主级动作也不属于此优先级，Breath 在生成的内部 Ghostty 配置中取消与自身快捷键冲突的内建绑定。输入焦点不在终端时由 Breath 直接处理，窗格级动作指向最后聚焦的终端窗格。macOS 系统生命周期快捷键不属于此规则。
_Avoid_: 动态快捷键回退、Agent 快捷键探测、Ghostty 快捷键配置

**应用配置（Application Settings）**：
由 Breath 拥有、只负责终端之外应用界面样式的配置。
_Avoid_: 终端配置、应用行为配置、Agent 项目配置

**网络代理（Network Proxy）**：
由用户在设置页选择的 Breath 网络访问策略，支持“不使用代理”“使用系统代理”和“使用手动代理”。手动代理接受 HTTP、HTTPS 或 SOCKS5 URL，以及可选用户名和密码；非密码字段随设置持久化，密码只保存在 macOS Keychain。该策略覆盖 Breath 内置网络请求和 Breath 发起的 Git HTTP(S) 操作，不修改 macOS 系统代理、终端内命令或 Sparkle 应用更新的网络行为。无效的手动代理配置必须阻止请求，不能静默退回直连。
_Avoid_: 系统网络设置、终端代理、Git 凭据、应用更新代理

**应用更新（Application Update）**：
Breath 通过 Sparkle 在应用内完成的版本检查、签名验证和安装流程。构建产物与更新包由公开 GitHub Releases 托管，签名后的 appcast 由同一 GitHub 仓库的 GitHub Pages 托管；客户端不使用自建更新服务、GitHub 登录或访问令牌。
_Avoid_: Breath 更新服务器、GitHub API 更新器、静默强制更新

**Agent CLI**：
在终端窗格中运行并持续交互的编码 Agent 命令行程序，可以由用户手动启动，也可以在用户启动任务后由 Breath 按任务配置启动。
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

**Agent 额度（Agent Quota）**：
当前 Agent CLI 登录账号由服务商官方来源提供的使用限制、剩余量、余额、消费上限、速率限制和重置时间；具体字段取决于当前登录方式和服务商。Breath 不根据本地对话、Token 或费用自行估算。额度检查优先通过服务商官方网络接口查询：先使用公开 API，没有公开 API 时可以在服务商未禁止且使用已获授权的前提下调用从官方客户端行为确认的私有接口；找不到可用网络接口时再使用官方 CLI 或官方协议。服务商禁止第三方复用凭据或无法确认授权时，不调用私有接口；也没有合规 CLI 或协议时，该 Agent 显示“不支持查询”。允许使用的凭据只存在于请求内存中，不由 Breath 持久化或对外暴露。
_Avoid_: 本地用量估算、Token 统计、费用估算、Breath 额度

**额度窗口（Quota Window）**：
服务商为一个 Agent 额度定义的独立限制周期或适用范围，保留官方名称、官方提供的额度数值和重置时间；同一 Agent 的多个额度窗口分别展示，不合并为单一额度。额度数值沿用官方计量方式：官方提供百分比就展示百分比，提供剩余量就展示剩余量，不在两者之间换算或推算缺失字段。
_Avoid_: 综合额度、平均额度、主要额度

**额度检查（Quota Check）**：
对当前已安装且受支持的 Agent CLI 的 Agent 额度及其可用状态的汇总；未安装的 Agent 不进入汇总，也不创建卡片。每个 Agent 独立产生结果，一个 Agent 失败不使其他结果失效。
_Avoid_: 全部受支持 Agent 清单、Agent 排行、用量估算

**额度检查状态（Quota Check Status）**：
单个已安装 Agent 在一次额度检查中的结果分类，只能是“查询中、可用、未登录、不支持查询、查询失败”之一。“查询失败”可以附带经过脱敏的简洁原因，但不得包含令牌、账号标识或其他凭据信息。
_Avoid_: 未知状态、旧数据、部分成功

**额度账号（Quota Account）**：
服务商在官方额度查询结果中返回的当前账号身份，用于说明额度归属；展示时遮罩邮箱或用户名。官方未返回账号身份时，Breath 不额外读取或推断。
_Avoid_: 完整邮箱、完整用户名、凭据账号推断

**额度服务商（Quota Provider）**：
当前 Agent CLI 默认会使用并为其提供额度的模型服务商。支持多个服务商的 Agent 只检查当前额度服务商，不遍历已配置但未启用的其他凭据；当前额度服务商返回的多个额度窗口仍全部展示。
_Avoid_: 全部已配置服务商、备用 API Key、模型列表
