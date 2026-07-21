# 全局 Skills 管理设计

状态：已确认
日期：2026-07-20

## 1. 目标

Breath 在主窗口提供面向当前 macOS 用户的全局 Skills 管理。用户可以查看各受支持 Agent CLI 中实际存在的全局 Skill，从 ZIP、公开 GitHub Repo 或 skills.sh 安装 Skill，并对具有可验证上游的 Skill 检查和安装更新，也可以按 Agent 卸载 Skill。

全局 Skill 不属于工作区。Skill 的实际文件始终由对应 Agent 的全局 Skill 目录拥有；Breath 不在应用数据目录维护规范副本，也不通过符号链接分发自己安装的 Skill。

## 2. 范围

首版包含：

- 汇总展示所有受支持 Agent CLI 的用户级全局 Skill，包括由 Breath、Agent CLI 或其他工具安装的内容。
- ZIP 导入。
- 指定公开 GitHub Repo、`owner/repo` 或 Skill 子目录 URL 后扫描。
- 在 skills.sh 中按关键词搜索。
- 从一个来源发现并多选一个或多个候选 Skill。
- 由用户明确选择一个或多个已安装 Agent 作为安装目标。
- 对 GitHub 和 skills.sh 来源的 Skill 检查更新并逐个更新。
- 按 Agent 卸载，普通目录移入 macOS 废纸篓。
- 展示解析错误、本地修改、可用更新和单项操作结果。

首版不包含：

- 项目级或工作区级 Skill。
- 私有 GitHub Repo、GitHub 登录或 Token 管理。
- 搜索整个 GitHub 上所有包含 `SKILL.md` 的仓库。
- Skill 创建、内置编辑器或内容发布。
- 一键更新全部 Skill。
- 自动重启 Agent、向既有会话注入 Skill，或保证运行中的 Agent 立即重新加载。
- Breath 账户、服务端或遥测。

## 3. 领域模型

### 3.1 全局 Skill 与安装副本

一个可识别 Skill 至少包含：

- 可解析的 `SKILL.md`。
- 非空 `name`。
- 非空 `description`。
- Skill 根目录及其中的脚本、引用、资源和其他文件。

`metadata.author` 是可选的 Skill 自声明作者。存在时展示作者，不把 GitHub owner、Repo 或 skills.sh 发布者推断为作者；作者不参与 Skill 唯一身份判断。

一个全局 Skill 可以在多个 Agent 中分别拥有安装副本。列表使用 `name + 规范化内容摘要` 聚合内容一致的副本，并在同一行展示多个 Agent；名称相同但内容不同的 Skill 是不同条目，通过 `description` 和已安装 Agent 自然区分，不增加“同名冲突”标签。

同一个 Agent 内只允许一个给定 `name` 的 Skill。安装另一个同名 Skill 时：

- 内容完全一致：显示“已安装”，不重复写入。
- 内容不同：在安装预览中展示现有与待安装的 `description` 和文件变化，由用户选择“覆盖”或“跳过”，默认跳过。
- Breath 不自动改名，也不在同一个 Skill 安装目标中创建第二个同名 Skill。

远程候选与既有副本首先比较 Skill 来源身份：skills.sh 使用稳定目录条目 ID，GitHub 使用 Repo 与来源内相对路径。来源身份一致表示同一个 Skill，即使 `name` 或内容版本已经变化；来源身份缺失或不一致时，安装预览再退化为同名与内容摘要比较。来源身份只用于安装、更新和对账，不在 Skills 浏览列表中展示。

### 3.2 候选 Skill

ZIP、GitHub Repo 或 skills.sh 结果解析出的内容先成为候选 Skill。一个来源可以包含多个候选 Skill，用户可以多选，但不能默认整仓安装。

候选状态分为：

- `valid`：满足必要结构，可安装。
- `warning`：存在名称格式、目录名不一致等非致命偏差，可在显示警告后安装。
- `invalid`：缺少 `SKILL.md`、YAML 无法解析，或缺少 `name` / `description`，不可安装。
- `unsafe`：路径越界、危险符号链接、特殊文件或资源限制异常，直接拒绝。

### 3.3 安装副本状态

每个“Skill × Skill 安装目标”副本独立具有以下信息：

- Agent、实际目录和存储形式（普通目录或外部符号链接）。
- 当前 `name`、`description`、内容摘要和解析诊断。
- 来源类型：ZIP、GitHub、skills.sh 或未知。
- 可验证上游、引用、安装 Commit 和安装时内容摘要（若存在）。
- 是否本地修改、是否存在更新、最近检查结果。

批量安装、更新或卸载按“Skill × Skill 安装目标”分别产生成功或失败结果。一个目标失败不回滚其他目标已经完成的操作，但单个目标内部不能留下半写入目录。

## 4. Agent 支持矩阵

Skill 安装目标与 Breath 的“受支持 Agent CLI”使用同一注册表。新增受支持 Agent 时，必须同时声明全局 Skill 目录解析规则并通过扫描、安装、更新和卸载契约测试，不能维护第二份手工 Agent 名单。

当前默认目录如下；实际操作必须尊重 Agent 支持的配置目录覆盖，并在界面展示解析后的真实路径：

| Agent | 默认全局 Skill 目录 |
|---|---|
| Codex | `~/.codex/skills` |
| Claude Code | `~/.claude/skills` |
| Gemini CLI | `~/.gemini/skills` |
| GitHub Copilot CLI | `~/.copilot/skills` |
| Qwen Code | `~/.qwen/skills` |
| Cursor Agent | `~/.cursor/skills` |
| Factory Droid | `~/.factory/skills` |
| OpenCode | `${XDG_CONFIG_HOME:-~/.config}/opencode/skills` |
| Pi | `~/.pi/agent/skills` |

Skill 安装目标必须同时满足：

1. 属于受支持 Agent CLI。
2. 本机已安装。
3. 能可靠解析其实际全局 Skill 目录。

未安装、版本不兼容或目录无法确认的 Agent 仍显示在选择器中，但禁用并说明原因。Breath 不猜测默认路径进行写入。Agent 已安装但 Skill 目录尚不存在时，可以在用户确认安装后创建该目录。

## 5. 信息架构

### 5.1 主窗口入口

- Skills 位于主窗口最左侧活动栏，在 Git 之后、设置之前。
- Skills 是与任务视图同级的全局主内容模式，不依赖当前工作区或工作会话。
- 无工作区时仍可进入。
- 选中按钮沿用活动栏统一的选中态。
- 打开 Skills 时隐藏工作区会话树；用户点击活动栏中的“工作区”后返回会话树与终端内容区。

### 5.2 Skills 页面

页面使用高密度原生“列表 + 详情”布局。

顶部区域包含：

- 标题与已识别 Skill 数量。
- 按 `name` 和 `description` 搜索。
- Agent 和状态筛选。
- 手动刷新。
- “安装 Skill…”主操作。

列表每行至少展示：

- `name`。
- 最多两行 `description`。
- `metadata.author` 声明的作者（若存在）。
- 已安装 Agent。
- 更新、本地修改或警告状态。

选中项的右侧详情展示：

- 完整 `description`、声明的作者与可展开的 `SKILL.md`。
- 文件清单、真实路径和“在 Finder 中显示”。
- 每个 Agent 副本的内容状态和存储形式。
- 更新与卸载操作。

窗口过窄时隐藏右侧详情，双击或按回车进入完整详情页。列表与所有操作必须支持键盘、VoiceOver、清晰焦点状态，并同时提供中英文文案。

### 5.3 无法识别的 Skill 项目

Agent Skill 目录中无法解析的文件夹或链接不计入正常 Skill 数量，也不伪装成正常 Skill。扫描结果可以保留这些项目的内部诊断信息，但 Skills 页面不展示它们，也不提供复制诊断、删除或其他管理操作。

## 6. 本地发现与刷新

打开 Skills 页面时先扫描本地目录并立即展示结果，不等待网络。扫描规则：

- 读取支持矩阵解析出的全部 Agent 全局 Skill 目录。
- 识别普通目录和符号链接。
- 将 `~/.agents/skills` 视为 skills CLI 管理的共享内容库。Agent 适配器显式声明该目录为额外发现根时（当前 Codex 支持），其中的 Skill 直接计为该 Agent 的已安装副本；其他 Agent 的 Skill 目录软链接到其中时，仍按对应 Agent 的已安装副本展示。共享库只读发现，不是 Breath 的安装或卸载目标。
- 只读解析 `~/.agents/.skill-lock.json`，按 skills CLI 的目录规范化规则将锁文件 Skill 标识关联到共享目录，并恢复 Repo 和来源内路径；规范化后发生歧义时不关联来源。Breath 不修改该清单，也不根据 `SKILL.md` 名称猜测来源。skills.sh 搜索返回结果后，只有锁文件 Repo、Skill 标识与结果中的 Repo、`skillId`、完整目录条目 ID 彼此一致，才视为同一目录条目。
- 不跟随形成循环或越界到不可读位置的链接。
- 解析 `SKILL.md` 的 YAML frontmatter，读取 `name`、`description` 及可选的 `license`、`compatibility`、`metadata` 和 `allowed-tools`。
- 内容摘要覆盖 Skill 目录内的真实文件内容，忽略 `.DS_Store` 等文件系统噪声，不执行任何文件。
- 目录变化时以节流的文件系统监听刷新；应用重新激活和手动刷新时进行完整对账。

外部工具创建或修改 Skill 后，列表以实际文件系统为准。数据库记录不能制造一个磁盘上不存在的“已安装 Skill”。

## 7. 安装流程

“安装 Skill…”打开统一的分步弹窗：

1. 在 `skills.sh`、`GitHub`、`ZIP` 三个平级 Tab 中选择来源，默认打开 `skills.sh`。
2. 解析来源。
3. 展示并多选候选 Skill。
4. 选择 Skill 安装目标。
5. 查看安装预览。
6. 确认并执行。
7. 展示逐 Skill、逐 Agent 结果。

返回上一步保留已有选择；关闭弹窗不写入文件。Skill 安装目标每次默认全部不勾选，不自动全选，也不记忆上一次选择；至少选择一个可用 Agent 后才能继续。

### 7.1 ZIP

- 来源页使用紧凑说明和“选择 ZIP…”操作，不使用超大空状态标题。
- 使用原生文件选择器，仅接受 ZIP 文件。
- 在受控临时目录解压。
- 拒绝绝对路径、`..` 越界、危险符号链接、设备文件及其他特殊文件。
- 对压缩包大小、解压后总大小、文件数、目录深度和候选数设置合理上限，防止 ZIP bomb 与失控扫描。
- 从标准 Skill 位置开始扫描；没有结果时进行有界递归扫描，排除 `.git`、依赖目录和构建产物。
- ZIP 安装没有 Skill 上游，不提供更新。

### 7.2 GitHub

- 接受公开 HTTPS Repo URL、`owner/repo`、分支 URL、Tag URL、Commit URL或 Skill 子目录 URL。
- 不搜索整个 GitHub，也不读取登录状态、Token 或 Git 凭据。
- Repo URL 跟随默认分支；分支 URL 跟随指定分支；Tag 与 Commit URL 视为固定版本。
- 安装时解析并记录实际 Commit；预览展示来源、引用和 Commit。
- 一个 Repo 可以发现多个候选 Skill。
- 私有 Repo 首版拒绝并提示改用 ZIP。

### 7.3 skills.sh

- 普通关键词调用隔离的 skills.sh Provider，通过 skills.sh 官方 CLI 使用的公开搜索入口检索。
- 只展示具有公开 GitHub 上游、可以由 Breath 原生安装的结果。skills.sh 搜索错误在当前 Tab 内联显示，不得弹出身份认证 Alert。
- 搜索结果展示名称、`description`、提交者、安装量及可用的安全审计信息，不展示完整来源字段。提交者取已验证 GitHub Repo 的 owner，仅表示目录条目的提交方，不等同于 Skill 的 `metadata.author`。
- 搜索输入使用短延迟 debounce 自动查询，不提供独立搜索按钮。
- 搜索结果不得以整行点击或无文字箭头触发远程下载。没有精确安装记录时，每行提供明确的“安装”按钮；skills.sh 目录条目 ID 与本机安装记录或受支持的共享清单精确一致时展示已安装 Agent。仍有可用 Agent 未安装时提供无省略号的“安装到其他 Agent”，所有可用 Agent 均已安装时只展示“此 Skill 已安装”。不得根据名称、作者、提交者或 Repo 猜测已安装。
- “安装到其他 Agent”必须先为本机已安装目录创建受控临时快照，再按正常目标选择与安装预览写入完整独立副本；该流程不得访问网络，也不得重新下载来源。快照中包含嵌套符号链接时拒绝复制，避免把共享库或其他外部路径带入目标 Agent。
- 安装预览优先比较来源身份，再比较 `name` 与内容摘要，明确区分“此 Skill 已安装”“已安装同名 Skill”和“已安装相同内容”，并决定是否需要覆盖。
- 搜索结果仅展示来源实际提供的信息；缺少 `description` 或安全审计时不展示占位文案或未知审计状态。
- skills.sh 指向的仓库同时包含仓库级 `SKILL.md` 与同名嵌套 Skill 时，优先选择目录名与目录条目 slug 匹配的嵌套 Skill，不能把 GitHub 压缩包的技术包装目录作为来源目录冲突展示给用户。
- 下载期间在对应结果行内展示进度；最终安装确认前不写入 Agent 目录。
- skills.sh 暂时不可用时只影响在线搜索，不影响本地列表、ZIP、指定 GitHub Repo、更新记录或卸载。

## 8. 安装预览与安全

任何来源都必须经过统一安装预览，至少展示：

- 来源与引用。
- 候选 Skill 的 `name`、`description` 和规范警告。
- 文件清单与可展开的 `SKILL.md`。
- 可选兼容性、许可证与工具声明。
- Skill 安装目标及真实目录。
- 已安装同名内容、将被替换的文件和默认“跳过”选择。
- skills.sh 可用的安全审计风险与检查时间。

安装预览和解析过程绝不运行脚本、Hook、构建命令或来源中的其他代码。安全审计只是辅助信息：未知不等于安全，高风险或严重风险需要额外确认，但不永久硬拦截，也不能跳过实际内容预览。

## 9. 写入与失败语义

Breath 为每个“候选 Skill × Skill 安装目标”独立执行：

1. 重新检查 Skill 安装目标、目录和同名占用。
2. 在目标目录同一文件系统上暂存完整新目录。
3. 如果覆盖既有目录，创建仅供本次操作回滚的临时备份。
4. 通过原子重命名替换单个目标。
5. 写入并提交 Skill 安装记录。
6. 成功后删除临时备份。

某个目标权限不足、磁盘空间不足、被外部进程改变或写入失败时，该目标恢复原状并单独报错；其他目标继续执行并保留成功结果。结果页将成功项和失败项分别列出，不用一个总错误掩盖部分成功。

Breath 自己安装的 Skill 始终是 Skill 安装目标目录中的完整独立副本，不创建符号链接，不在 Breath 应用数据目录保存 Skill 内容副本。

## 10. 安装记录与对账

Breath 安装成功后，在现有 SQLite 数据库中保存非侵入式安装记录。ZIP 记录只包含来源分类及副本身份；GitHub 或 skills.sh 记录还至少包含：

- Agent 类型。
- 安装路径。
- Skill `name`。
- 来源类型、来源标识和 Repo URL。
- Skill 来源身份：skills.sh 目录条目 ID，或 GitHub Repo 与来源内相对路径。
- Skill 在来源中的相对路径。
- 跟随引用或固定引用。
- 安装 Commit。
- 安装时内容摘要。
- 安装与最近更新时间。

ZIP 来源分类不构成 Skill 上游，不参与更新检查，也不产生“本地已修改”状态。

Breath 不向 Skill 目录写入 `.breath-*` 文件、扩展属性或其他私有标记。数据库记录保存来源分类；只有远程记录包含上游关联。记录不是已安装状态的事实来源：

- 记录存在而目录消失：移除或失效该记录。
- 路径和 Skill 身份一致但内容变化：标记“本地已修改”，保留上游。
- 原路径被另一个 Skill 占用或身份无法确认：解除关联并降级为“来源未知”。
- Breath 数据被删除：Skill 文件保持可用，但失去 Breath 记录的更新能力。

Breath 可以只读识别能安全匹配的生态兼容清单，例如 skills CLI 的全局锁定信息；不修改其他工具的清单，也不根据 Skill 名称猜测上游。

对于 skills CLI 的共享安装，`~/.agents/skills` 中的目录提供本地内容，`~/.agents/.skill-lock.json` 提供可验证来源身份。是否计为某个 Agent 已安装由该 Agent 适配器声明的发现根和 Agent 自身 Skill 目录中的符号链接共同决定；当前 Codex 会直接发现全局 `~/.agents/skills`。Breath 监听共享目录和锁文件的外部变化；识别和复制过程中不改写共享目录、锁文件或既有符号链接。从共享副本安装到其他 Agent 时，只在目标 Agent 目录创建完整副本，并为该副本保留共享来源身份；共享来源没有可验证 Commit，因此不由 Breath 提供更新检查。

## 11. 更新

只有具有可验证 Skill 上游的 GitHub 或 skills.sh 副本可以更新。ZIP 和来源未知 Skill 不显示更新操作。

### 11.1 检查时机

- 只有用户打开 Skills 页面时自动检查。
- 先展示本地数据，再异步查询。
- 同一会话使用网络缓存，手动刷新可以重新检查。
- 用户没有打开 Skills 页面时，Breath 不在后台访问 GitHub 或 skills.sh。
- 网络失败保留本地列表并显示可重试状态。

### 11.2 引用语义

- Repo 默认分支与指定分支检查其最新 Commit。
- Tag 和 Commit 为固定版本，不检查更新。
- 只有 Skill 目录实际内容变化才显示更新，不因无关 Repo 文件变化制造更新。

### 11.3 更新操作

- 首版逐个 Skill 更新，不提供“更新全部”。
- 同一上游、存在更新且未本地修改的 Agent 副本默认勾选。
- 本地修改副本默认不勾选，必须由用户主动选择。
- 不同上游分开更新，不能混入同一次操作。
- 更新必须复用安装预览，展示旧、新 Commit、文件变化、`description` 变化和将被覆盖的本地修改。
- 用户确认前只检查，不写入；失败时保留该 Agent 的旧版本。

## 12. 外部符号链接

外部工具安装的符号链接 Skill 正常扫描和展示，但 Breath 不自动迁移：

- 卸载某个 Agent 时只移除该 Agent 的链接，不删除共享目标。
- 更新某个 Agent 时，预览明确说明存储形式变化。
- 用户确认更新后，Breath 将所选链接替换为该 Agent 目录中的独立新版副本，不修改共享目标或其他 Agent 链接。

## 13. 卸载

- 用户在详情中选择一个或多个 Agent 副本，也可以选择该条目的全部 Agent。
- 确认页显示 Agent、真实路径和将移除的存储形式。
- 普通目录通过 macOS 文件协调能力移入废纸篓，不永久递归删除。
- 符号链接只移除链接本身，不跟随和删除目标。
- 每个 Agent 独立执行；失败不撤销其他成功卸载。
- 不删除原始 ZIP、GitHub Repo、skills.sh 条目或未选择 Agent 的副本。
- 成功后删除对应 Breath 安装记录并刷新列表。

## 14. Agent 运行时

安装、更新或卸载不自动重启 Agent CLI，不停止终端，不修改工作会话，也不向现有 Agent 对话注入内容。结果页提示“可能需要新建或重启 Agent 会话后生效”；如果某个 Agent 有可验证的热加载行为，可以由支持矩阵提供更精确提示。

## 15. 技术边界

### 15.1 原生实现

Breath 使用 Swift 原生实现来源解析、下载、ZIP 校验、目录扫描、内容摘要、安装、更新与卸载。不调用 `npx skills`，不要求 Node.js，也不发送 `skills` CLI 遥测。

skills.sh 被封装为可替换 Provider。接口变化、限流或不可用时返回独立错误；不能为了恢复搜索而隐式引入 Breath 后端、账户或追踪。未来若官方访问方式要求服务端，必须作为新的产品与隐私决策处理。

### 15.2 推荐模块

- `BreathSkills`：Skill 领域类型、Agent Skill 目录注册、扫描、来源解析、校验、安装、更新、卸载和文件监听。
- `BreathPersistence`：Skill 安装记录 migration 与 repository 实现。
- `BreathApp`：Skills 导航模式、列表、详情、安装向导、预览和结果界面。
- `BreathAgents`：受支持 Agent 描述符提供 Skill 能力与实际目录解析契约，保证新增 Agent 同步接入。

按 Agent 全局目录串行化写操作，防止安装、更新、卸载及外部刷新互相覆盖；不同 Agent 可以并行处理，并按既定语义分别产生结果。

### 15.3 错误与隐私

- 默认显示简短可操作原因，并允许复制经过清理的详细信息。
- 不展示进程环境变量、凭据、URL 中的敏感查询参数或本地无关路径。
- 不上传 Skill 内容、安装目录、搜索历史或 Agent 列表。
- 网络请求只发送完成 GitHub 解析或 skills.sh 查询所需的信息。

## 16. 验收标准

1. 左侧活动栏按“工作区、任务、Git、Skills、设置”排序；无工作区时仍可进入 Skills，点击“工作区”后返回会话树与终端。
2. 页面汇总 9 个受支持 Agent 实际目录中的普通目录和符号链接 Skill，不限于 Breath 安装项。
3. 内容一致的跨 Agent 副本聚合为一行；同名但内容不同的 Skill 分行并展示各自 `description`，存在 `metadata.author` 时展示作者，不显示“同名冲突”或来源字段。
4. 无法识别的目录不计入 Skill 数量，也不在 Skills 页面展示或提供诊断与管理操作。
5. ZIP、指定公开 GitHub Repo 和 skills.sh 关键词搜索都能产生候选列表；多 Skill 来源不会默认全装。
6. Skill 安装目标默认全部不选；未安装、版本不兼容或真实 Skill 路径无法确认的 Agent 禁用并解释原因。
7. 任意安装都经过文件、`SKILL.md`、目标和覆盖内容预览；导入过程不执行来源代码。
8. 安装预览先用来源身份确认同一个远程 Skill，再处理同名占用；相同内容不重复写入，不同内容默认跳过，只有用户明确选择才覆盖。
9. 批量安装允许部分成功，失败目标保持原状并单独报告，成功目标不回滚。
10. Breath 安装项是各 Agent 目录中的独立完整副本，不创建 Breath 中心副本、分发符号链接或 Skill 目录私有元数据。
11. GitHub/skills.sh 安装记录保存在 SQLite；删除 Breath 数据不破坏 Skill，只使来源与更新能力不可确认。
12. 外部修改被识别为“本地已修改”，更新前展示将覆盖的变化；身份无法确认时降级为来源未知。
13. 只有默认分支或指定分支来源检查更新；Tag、Commit、ZIP 和来源未知项不显示更新。
14. 打开 Skills 页面才触发远程检查；应用其他区域不后台联网；网络失败不影响本地列表和操作。
15. 更新逐 Skill确认，不提供更新全部；本地修改目标不默认勾选，失败时保留旧版本。
16. 外部符号链接可展示；卸载只移除链接，显式更新才把所选 Agent 转成独立副本。
17. 普通 Skill 卸载移入废纸篓，并按 Agent 分别报告结果，不删除来源或未选择副本。
18. 安装、更新和卸载不重启 Agent 或终端，并提示可能需要新会话后生效。
19. Skills 页面、安装向导、预览、结果和错误状态支持键盘、VoiceOver、中英文及系统深浅外观。
20. 新增受支持 Agent 时，缺少 Skill 目录解析与完整契约测试会使支持矩阵测试失败，防止功能遗漏。
21. 功能不要求 Node.js，不调用 `npx skills`，不引入 Breath 后端、账户或遥测。

## 17. 决策与外部依据

- [ADR 0032：原生管理全局 Skill，不依赖 Node.js 或 Breath 后端](../adr/0032-manage-global-skills-natively-without-node-or-backend.md)
- [ADR 0033：将 Skill 直接安装到各 Agent 目录](../adr/0033-install-skills-directly-into-agent-directories.md)
- [ADR 0034：在 Skill 目录之外保存来源记录](../adr/0034-store-skill-provenance-outside-skill-directories.md)
- [ADR 0035：区分 Skill 安装来源与 Skill 上游](../adr/0035-distinguish-skill-origin-from-upstream.md)
- [Breath 领域词汇](../../CONTEXT.md)
- [Agent Skills 格式规范](https://agentskills.io/specification)
- [Agent Skills 客户端实现指南](https://agentskills.io/client-implementation/adding-skills-support)
- [skills.sh CLI 文档](https://www.skills.sh/docs/cli)
- [skills.sh API 文档](https://www.skills.sh/docs/api)
- [vercel-labs/skills](https://github.com/vercel-labs/skills)
