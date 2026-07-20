# Breath Git 工作台：对齐 JetBrains 的完整 Git GUI

Status: implementation-complete-pending-manual-accessibility-acceptance

## Problem Statement

Breath 目前只有面向工作区状态和只读 Diff 的初步 Git 能力，用户仍需离开 Breath，借助 JetBrains IDE、独立 Git 客户端或终端完成提交、分支管理、历史浏览、冲突解决、暂存、变基、推送等日常 Git 工作。这打断了以工作会话为中心的工作流，也使 Breath 无法成为承载完整开发活动的统一桌面工作台。

本需求要在 Breath 内集成一个通用、完整、原生 macOS 风格的 Git GUI。产品行为、信息架构、术语和交互语义应尽量与 JetBrains 系列 IDE 的 Commit、Git Log、Branches、Diff、Merge、Stash、Shelf 等 Git 工具保持一致；视觉表现仍遵循 Breath 自身设计语言，不要求像素级复制 JetBrains。

Git 工作台只使用“当前选中的工作会话所属工作区”来确定操作目标。除此之外，它不与 Agent 上下文、Agent 生命周期、终端 Pane 或会话任务模型耦合。用户在 Git 工作台执行的所有操作都是普通 Git 操作，结果以磁盘上的仓库和 Git 自身状态为准。

首次对用户交付时，必须完整实现本文所有已确认能力。不得先公开一个仅包含 Changes、Log 或 Commit 的残缺 Git 页面，并把其余已确认能力视为后续增强。

## Solution

在左侧栏底部、任务视图按钮左侧新增 Git 工作台入口。入口始终可见；没有选中工作会话时禁用，并提示用户先选择工作会话。点击后，右侧主区域进入完整 Git 页面，左侧栏继续保留。Git 页面自动绑定当前选中工作会话所属的工作区；切换到其他工作区中的工作会话时，Git 页面随之切换目标工作区。

完整 Git 页面采用适合 Breath 大画布的三列布局，同时承载 JetBrains Commit 与 Git Log 的主要能力：

- 顶部工具栏提供 Git Root、当前分支、刷新、Fetch、Pull/Update、Push、搜索和常用操作。
- 左列承载分支、标签、Git Root、本地变更、Changelist 或 Staging、提交信息与提交操作。
- 中列承载可分页、可虚拟化的 Commit Graph 和历史过滤。
- 右列承载本地 Diff、提交详情、提交文件与历史 Diff。
- 底部提供可折叠 Console，展示 Breath 发起的 Git 命令、进度和结果。

页面支持多 Git Root，并提供 All Repositories 聚合视图。Changes、Log 和 Commit 可以跨 Root 聚合展示；会改变仓库历史或分支状态的操作默认只作用于用户明确选择的单个 Root。跨 Root 同步分支操作是显式开启的工作区能力，执行前展示计划，失败时按 Root 呈现结果，不隐式回滚。

默认使用 JetBrains 风格的 Changelist 管理本地变更，同时提供可切换的原生 Git Staging Area 模式。两种工作流互斥显示，但 Changelist 元数据在切换到 Staging 后仍保留，切回时恢复。Changelist 与 Staging 均支持文件、Hunk 和行级提交选择。

Git 工作台以用户安装的 Git CLI 为唯一 Git 后端，尊重用户已有的 Git 配置、Hooks、签名、Credential Helper、SSH Agent、Git LFS 和环境。Breath 不保存 Git 密码、Token 或 SSH Passphrase。所有写操作按 Git Root 串行执行；不同 Root 可以并行。外部终端或其他程序对仓库的修改通过文件事件和 Git 状态重新读取被感知，Git 和磁盘始终是事实来源。

对于 Breath 发起的高风险操作，Git 工作台在操作前尽力创建本地 Git Safety Snapshot，供用户按文件或片段检查和恢复。该能力不是连续 Local History，不承诺捕获终端、Agent 或其他外部程序产生的所有修改，也不会因为快照失败而阻塞 Git 操作。

## User Stories

1. 作为 Breath 用户，我希望在左侧栏底部看到 Git 工作台按钮，从而可以从任何工作会话快速进入 Git 页面。
2. 作为 Breath 用户，我希望 Git 按钮位于任务视图按钮左侧，从而保持已确认的底栏入口顺序。
3. 作为没有选中工作会话的用户，我希望 Git 按钮保持可见但处于禁用状态，从而知道 Breath 具备 Git 能力但当前缺少目标工作区。
4. 作为没有选中工作会话的用户，我希望悬停或聚焦禁用按钮时看到“请先选择工作会话”一类的本地化说明。
5. 作为已选中工作会话的用户，我希望点击 Git 按钮后右侧主区域打开完整 Git 页面，而左侧栏仍然可用。
6. 作为使用多个工作会话的用户，我希望 Git 页面始终操作当前选中工作会话所属的工作区。
7. 作为在同一工作区切换工作会话的用户，我希望 Git 页面保持当前 Git 页面状态，不进行无意义的重新初始化。
8. 作为切换到另一工作区工作会话的用户，我希望 Git 页面自动切换到新工作区对应的 Git 状态。
9. 作为正在执行 Git 操作的用户，我希望离开 Git 页面或切换工作区时操作继续运行。
10. 作为同时使用多个工作区的用户，我希望 Git 入口显示全局运行中和失败状态徽标。
11. 作为看到 Git 状态徽标的用户，我希望可以打开跨工作区操作队列，并跳转回对应工作区查看详情。
12. 作为 Breath 用户，我希望 Git 工作台除了目标工作区选择外不依赖 Agent 状态、Agent 上下文或终端 Pane。
13. 作为 Breath 用户，我希望 Git 页面同时显示 Changes 和 Log 的主要内容，而不必在两个互斥标签页之间来回切换。
14. 作为 Breath 用户，我希望通过可拖动分隔线调整三列和 Console 的尺寸。
15. 作为返回某个工作区的用户，我希望该工作区上次保存的栏宽、Console 高度和折叠状态得到恢复。
16. 作为查看本地变更的用户，我希望最后选择的文件、Hunk、行或 Changelist 决定右侧显示的本地 Diff。
17. 作为查看提交历史的用户，我希望最后选择的 Commit 决定右侧显示的提交详情、文件和 Diff。
18. 作为在本地变更与历史之间切换的用户，我希望两侧各自保留选择、滚动位置和过滤条件。
19. 作为用户，我希望右侧标题清楚标识当前内容来自 Local Changes 还是某个 Commit，避免误判操作对象。
20. 作为熟悉 JetBrains Git 工具的用户，我希望 Breath 使用熟悉的信息架构、术语、颜色语义和操作顺序。
21. 作为 Breath 用户，我希望 Git 页面保持原生 macOS 和 Breath 的视觉风格，而不是机械复制 JetBrains 的像素表现。
22. 作为色觉障碍用户，我希望新增、修改、删除、冲突、传入和传出状态不只依赖颜色表达。
23. 作为包含单个 Git 仓库的工作区用户，我希望 Breath 自动发现仓库根目录并立即显示当前分支与 Changes。
24. 作为打开 Git 仓库子目录的用户，我希望 Breath 能检测工作区上级目录中的仓库根，并明确警告该 Root 位于工作区之外。
25. 作为收到上级仓库提示的用户，我希望显式确认后才允许 Breath 操作工作区之外的仓库内容。
26. 作为包含嵌套独立仓库的工作区用户，我希望每个仓库被识别为独立 Git Root。
27. 作为多仓库工作区用户，我希望可以在单个 Git Root 与 All Repositories 之间切换。
28. 作为选择 All Repositories 的用户，我希望 Changes 按 Root 清晰分组并聚合展示。
29. 作为选择 All Repositories 的用户，我希望 Log 可以聚合多个 Root，同时让每个 Commit 的来源 Root 始终可辨认。
30. 作为跨 Root 提交的用户，我希望 Breath 在执行前列出每个 Root 将产生的独立 Commit。
31. 作为跨 Root 提交的用户，我希望每个 Root 分别生成普通 Git Commit，而不是伪造一个跨仓库原子提交。
32. 作为跨 Root 提交遇到部分失败的用户，我希望看到各 Root 的成功或失败结果，并且 Breath 不隐藏已经成功产生的 Commit。
33. 作为执行 Checkout、Merge、Rebase、Reset 或 Push 的用户，我希望操作默认只作用于明确选择的一个 Git Root。
34. 作为确实需要多个 Root 同步分支操作的用户，我希望可以在工作区设置中显式启用该能力。
35. 作为执行同步分支操作的用户，我希望执行前看到涉及的 Root、源分支、目标分支和操作顺序。
36. 作为同步分支操作部分失败的用户，我希望 Breath 提供针对已成功 Root 的回退建议，而不是自动做不可见回滚。
37. 作为初次使用 Git 工作台的用户，我希望默认使用 JetBrains 风格的 Changelist 工作流。
38. 作为偏好原生 Git Index 的用户，我希望可以把当前工作区切换到 Staging Area 工作流。
39. 作为切换工作流的用户，我希望 Changelist 与 Staging 在界面上互斥，避免同时出现两套相互矛盾的提交模型。
40. 作为从 Changelist 切换到 Staging 的用户，我希望已有 Changelist 分组元数据被保留。
41. 作为从 Staging 切回 Changelist 的用户，我希望之前的 Changelist 分组尽可能原样恢复。
42. 作为 Changelist 用户，我希望创建、重命名、删除和设置默认 Changelist。
43. 作为 Changelist 用户，我希望把完整文件移动到另一个 Changelist。
44. 作为 Changelist 用户，我希望把单个 Hunk 移动到另一个 Changelist。
45. 作为 Changelist 用户，我希望把选中的修改行移动到另一个 Changelist。
46. 作为 Changelist 用户，我希望按 Changelist 分别填写或保留提交草稿并独立提交。
47. 作为仓库被外部程序修改的 Changelist 用户，我希望 Breath 尽力重映射变更分组，无法安全判断时明确标记待确认，而不是静默提交错误内容。
48. 作为 Changelist 用户，我希望只提交选中的文件、Hunk 或行，其他变更以及用户已有的 Index 内容保持不变。
49. 作为 Staging 用户，我希望分别看到 Unstaged 和 Staged 变更。
50. 作为 Staging 用户，我希望按文件 Stage 和 Unstage。
51. 作为 Staging 用户，我希望按 Hunk Stage 和 Unstage。
52. 作为 Staging 用户，我希望按选中行 Stage 和 Unstage。
53. 作为需要精确构造 Index 的用户，我希望看到 HEAD、Staged、Local 三方内容并可编辑 Staged 结果。
54. 作为 Staging 用户，我希望外部终端修改 Index 后 Breath 自动刷新到真实状态。
55. 作为提交代码的用户，我希望输入多行 Commit Message，并在工作区切换或应用重启后恢复未提交草稿。
56. 作为提交代码的用户，我希望使用最近提交信息和仓库 Commit Template。
57. 作为提交代码的用户，我希望执行 Commit。
58. 作为提交后立即同步的用户，我希望执行 Commit and Push。
59. 作为修正最近提交的用户，我希望执行 Amend 并清楚看到被修改的 Commit。
60. 作为提交新文件的用户，我希望在 Changes 中看到 Unversioned Files，并可选择加入提交。
61. 作为提交部分修改的用户，我希望提交前看到最终文件、Hunk、行和 Root 计划。
62. 作为启用了 Git Commit Hook 的用户，我希望 Breath 默认正常运行 Hook。
63. 作为明确知道风险的用户，我希望可以针对本次提交显式跳过可跳过的 Commit Hook。
64. 作为工作区维护者，我希望配置提交前运行的格式化、Lint、类型检查或测试 Shell 命令。
65. 作为提交前检查失败的用户，我希望提交默认被阻止，并看到完整、已脱敏输出。
66. 作为修复检查问题的用户，我希望可以从失败状态重新运行检查并继续提交。
67. 作为用户，我希望 Breath 不伪装成 IDE 编译器，不提供无法可靠实现的 Inspection 或 TODO 分析检查。
68. 作为查看分支的用户，我希望浏览本地分支、远程分支和 Tags。
69. 作为分支很多的用户，我希望按名称搜索、按前缀分组和收藏常用分支。
70. 作为选择分支的用户，我希望看到当前分支、Upstream、Incoming 和 Outgoing 数量。
71. 作为创建分支的用户，我希望从当前 HEAD、选中分支或选中 Commit 创建分支。
72. 作为切换分支的用户，我希望执行 Checkout，并在有潜在覆盖风险时看到影响说明。
73. 作为跟踪远程分支的用户，我希望 Checkout 远程分支并建立本地跟踪关系。
74. 作为更新已有本地分支的用户，我希望使用 JetBrains 风格的 Checkout and Update 工作流。
75. 作为管理分支的用户，我希望重命名和删除本地分支。
76. 作为管理远程分支的用户，我希望删除远程分支前看到远程和完整引用。
77. 作为管理跟踪关系的用户，我希望设置或取消 Upstream。
78. 作为管理仓库连接的用户，我希望查看、新增、编辑和删除 Remotes。
79. 作为浏览历史的用户，我希望看到包含本地和远程引用的 Commit Graph。
80. 作为浏览历史的用户，我希望 Commit Graph 清楚展示分叉、合并、分支与 Tag 装饰。
81. 作为历史很长的仓库用户，我希望 Log 渐进加载、分页和虚拟化，而不是阻塞整个页面。
82. 作为查找提交的用户，我希望按作者、时间、路径、分支、Root 和文本过滤 Log。
83. 作为知道对象标识的用户，我希望跳转到 Commit Hash、分支或 Tag。
84. 作为选择 Commit 的用户，我希望查看作者、时间、父提交、完整消息、Refs 和变更文件。
85. 作为选择 Commit 文件的用户，我希望在右侧查看相对父提交的 Diff。
86. 作为查看某个文件演进的用户，我希望打开 File History。
87. 作为理解代码来源的用户，我希望打开 Blame/Annotate，并从行跳转到对应 Commit。
88. 作为合并功能分支的用户，我希望从分支菜单或 Log 发起 Merge。
89. 作为整理提交历史的用户，我希望发起普通 Rebase。
90. 作为精细整理本地历史的用户，我希望执行 Interactive Rebase。
91. 作为 Interactive Rebase 用户，我希望重新排序、Squash、Fixup、Drop、Edit 和 Reword 本地 Commit。
92. 作为需要移植提交的用户，我希望 Cherry-pick 一个或多个 Commit。
93. 作为撤销已发布提交的用户，我希望通过 Revert 生成反向 Commit。
94. 作为只需取回部分历史改动的用户，我希望把选中 Commit 中的文件或选定修改应用到工作树。
95. 作为刚提交错误内容的用户，我希望 Undo Last Commit，并明确选择保留修改的方式。
96. 作为需要移动 HEAD 的用户，我希望执行 Soft、Mixed、Hard 和 Keep Reset。
97. 作为修改较早本地提交的用户，我希望把当前修改 Amend 或 Fixup 到选中的未发布 Commit。
98. 作为只想推送到历史中某一点的用户，我希望可以 Push up to Selected Commit。
99. 作为操作受保护分支的用户，我希望 Breath 阻止 Force Push、Drop、Edit 或重写已发布历史。
100. 作为工作区维护者，我希望默认保护 main 和 master，并配置更多分支名称或模式。
101. 作为即将执行高风险历史操作的用户，我希望确认页显示 Git Root、当前分支、目标分支和受影响 Commit。
102. 作为推送代码的用户，我希望在 Push 前审阅 Outgoing Commits、文件和 Diff。
103. 作为推送代码的用户，我希望选择目标 Remote 和目标 Branch。
104. 作为发布版本的用户，我希望可以选择是否推送 Tags。
105. 作为 Push 被拒绝的用户，我希望选择 Merge 或 Rebase 更新策略，并可记住该工作区偏好。
106. 作为确实需要覆盖远程历史的用户，我希望 Breath 只提供 `--force-with-lease`，从不提供无租约 Force Push。
107. 作为执行 Fetch 的用户，我希望看到各 Remote 的结果、更新引用和错误。
108. 作为执行 Pull/Update 的用户，我希望选择或使用已保存的 Merge/Rebase 策略。
109. 作为用户，我希望 Breath 默认每 20 分钟自动 Fetch，并允许修改间隔或完全禁用。
110. 作为仓库发生冲突的用户，我希望 Changes 中出现明确的 Merge Conflicts 节点。
111. 作为在终端触发冲突的用户，我希望 Breath 自动识别进行中的 Merge、Rebase、Cherry-pick 或 Revert。
112. 作为解决冲突的用户，我希望使用三栏合并器查看两侧输入、Base 和可编辑 Result。
113. 作为解决简单冲突的用户，我希望一键应用所有无冲突修改。
114. 作为逐块解决冲突的用户，我希望接受或忽略任一侧，并直接编辑最终结果。
115. 作为完成冲突解决的用户，我希望标记文件已解决并执行 Continue。
116. 作为无法继续当前序列操作的用户，我希望执行 Skip 或 Abort。
117. 作为处于 Merge/Rebase 等中间状态的用户，我希望不兼容操作被禁用并解释原因。
118. 作为查看文本变更的用户，我希望在 Side-by-side 与 Unified Diff 之间切换。
119. 作为审阅多个差异的用户，我希望跳转到上一个或下一个差异以及上一个或下一个文件。
120. 作为审阅格式化变更的用户，我希望配置忽略空白、显示空白字符、Soft Wrap 和折叠未变更区域。
121. 作为审阅大文件的用户，我希望在 Diff 内搜索和复制文本。
122. 作为修改工作树文件的用户，我希望直接编辑 Diff 的本地一侧，并立即写入真实文件。
123. 作为精确构造 Index 的用户，我希望编辑 Staged 结果时立即写入真实 Git Index。
124. 作为查看二进制或超大文件的用户，我希望看到类型、大小和可用系统预览，而不是自动生成不可用的文本 Diff。
125. 作为撤销本地修改的用户，我希望按文件、Hunk 或行执行 Rollback。
126. 作为执行 Rollback 的用户，我希望在不可逆覆盖前看到明确确认和影响范围。
127. 作为执行 Breath 高风险 Git 操作的用户，我希望系统在操作前尽力创建 Git Safety Snapshot。
128. 作为 Git Safety Snapshot 用户，我希望 Snapshot 覆盖 Breath 发起的 Rollback、Checkout、Reset、Merge、Rebase、Stash Apply 等潜在破坏性操作。
129. 作为 Git Safety Snapshot 用户，我希望按操作、时间、Root 和受影响文件浏览快照。
130. 作为 Git Safety Snapshot 用户，我希望将 Snapshot 与当前状态比较，并恢复完整文件或选定片段。
131. 作为管理本地存储的用户，我希望默认保留最近 5 个“发生修改的工作日”的 Snapshot。
132. 作为管理本地存储的用户，我希望修改 Snapshot 保留时长，并通过设为 0 完全禁用。
133. 作为磁盘空间紧张的用户，我接受缓存系统提前清理 Snapshot，但希望界面明确说明该能力不作永久保证。
134. 作为执行 Git 操作的用户，我希望 Snapshot 创建失败或不可用时操作仍可继续，并得到非阻塞提示。
135. 作为通过终端或 Agent 修改文件的用户，我希望产品明确说明 Git Safety Snapshot 不是覆盖所有外部变更的连续 Local History。
136. 作为使用标准 Git 协作的用户，我希望创建 Git Stash，并选择消息、包含未跟踪文件和保留 Index 等选项。
137. 作为使用 Git Stash 的用户，我希望预览、Apply、Pop 和 Drop Stash。
138. 作为需要 Breath 本地补丁集合的用户，我希望把选定文件、Hunk、行或 Changelist Shelve。
139. 作为使用 Shelf 的用户，我希望预览 Shelf、部分恢复、多次应用、删除和重命名 Shelf。
140. 作为跨工具传递补丁的用户，我希望导入和导出标准 Patch。
141. 作为同时使用 Stash 与 Shelf 的用户，我希望两者语义和存储位置清楚区分。
142. 作为偏好不同组织方式的用户，我希望选择把 Stash 与 Shelf 合并展示或分别展示。
143. 作为 HTTPS Remote 用户，我希望 Breath 在 Git 请求时提供用户名、密码或 Token 输入界面。
144. 作为 SSH Remote 用户，我希望 Breath 支持 SSH Passphrase 和首次 Host Key 确认交互。
145. 作为已配置 Credential Helper、SSH Agent 或 macOS Keychain 的用户，我希望 Breath 复用现有配置。
146. 作为输入凭证的用户，我希望凭证只传递给当前 Git 进程，是否持久化由用户的 Helper 决定。
147. 作为安全敏感用户，我希望 Breath 永不把密码、Token、Passphrase 或秘密环境变量写入 Console 和持久化日志。
148. 作为使用自定义 Git 的用户，我希望在应用设置中指定 Git 可执行文件路径并执行 Test。
149. 作为普通用户，我希望 Breath 自动发现系统可用的 Git CLI。
150. 作为 Git 版本较旧的用户，我希望 Breath 检测能力并对不支持的操作给出本地化说明和实际版本信息。
151. 作为拥有自定义 `.gitconfig` 的用户，我希望 Breath 遵循别名以外的标准配置、Hooks、签名、Credential Helper、SSH 和环境行为。
152. 作为使用 GPG 或 SSH 签名的用户，我希望 Commit 与 Tag 签名交互由已安装 Git 和现有签名工具正常完成。
153. 作为观察仓库状态的用户，我希望 Breath 使用文件事件自动刷新工作树、Index、Refs 和进行中的操作状态。
154. 作为仓库频繁变化的用户，我希望刷新被合并和节流，避免界面抖动或重复运行昂贵命令。
155. 作为希望确认最新状态的用户，我希望随时手动 Refresh。
156. 作为运行写操作的用户，我希望同一 Git Root 上由 Breath 发起的写操作串行执行。
157. 作为多 Root 用户，我希望互不相关的 Root 可以并行执行 Git 操作。
158. 作为同时在终端使用 Git 的用户，我希望 Breath 不杀死、不接管外部 Git 进程。
159. 作为遇到 `index.lock` 的用户，我希望 Breath 不自动删除锁文件，而是展示原始 Git 错误并允许稍后刷新。
160. 作为关闭 Git 页面或切换到其他 Breath 页面的人，我希望正在进行的 Git 命令不被取消。
161. 作为退出 Breath 的用户，我希望只读加载可以直接取消。
162. 作为退出 Breath 时仍有写操作运行的用户，我希望应用等待操作完成，或让我显式请求 Git 支持的正常取消。
163. 作为退出 Breath 的用户，我希望应用不以强制杀进程的方式终止认证或 Git 子进程。
164. 作为在冲突状态退出的用户，我希望下次启动时 Breath 从仓库状态重新发现冲突并继续处理。
165. 作为查看 Git 执行细节的用户，我希望底部 Console 展示 Breath 发起的命令、开始结束时间、退出状态和已脱敏输出。
166. 作为需要更多页面空间的用户，我希望折叠 Console，并通过运行或失败提示再次展开。
167. 作为返回工作区排查问题的用户，我希望 Console 默认保留最近 7 天或 500 条命令，以先达到者为限。
168. 作为隐私敏感用户，我希望清空 Console 历史或关闭持久化；关闭后仅保留当前会话记录。
169. 作为查看并发操作的用户，我希望 Console 或操作队列展示等待、运行、成功、失败和可取消状态。
170. 作为工作区没有 Git 仓库的用户，我希望看到明确空状态和 `git init` 操作。
171. 作为初始化仓库的用户，我希望 Breath 只在我明确选择的目录执行 `git init`，绝不自动初始化。
172. 作为克隆仓库的用户，我希望输入 Remote URL 和新目录后执行 Clone。
173. 作为 Clone 成功的用户，我希望新目录自动加入 Breath Workspace 列表。
174. 作为选择非空目标目录的用户，我希望 Breath 拒绝覆盖并要求选择安全的新目录。
175. 作为包含 Git Submodule 的用户，我希望父仓库中清楚标识 Submodule、指针变化和脏状态。
176. 作为 Submodule 用户，我希望执行 Init、Update 和 Sync URL。
177. 作为需要深入 Submodule 的用户，我希望把它作为独立 Git Root 进入和操作。
178. 作为多 Root 提交用户，我希望 Submodule 不被当作普通嵌套目录递归提交。
179. 作为执行同步多 Root 分支操作的用户，我希望该操作不会自动传播到 Submodule。
180. 作为使用 Git LFS 的用户，我希望 Breath 通过用户安装的 Git LFS 和 `.gitattributes` 正常运行过滤器与 Hooks。
181. 作为查看 LFS 文件的用户，我希望识别 Pointer 信息，并在实际对象已下载时预览真实内容。
182. 作为使用 Git LFS 的用户，我希望 Fetch/Pull LFS 对象并查看 LFS Locks。
183. 作为没有安装 Git LFS 的用户，我希望相关操作明确说明缺失能力，而不是由 Breath 自动安装。
184. 作为使用托管平台 LFS Lock 的用户，我接受 Breath 只调用现有 Git LFS 能力，不管理平台账号。
185. 作为大型仓库用户，我希望页面先快速显示当前分支和 Changes，再渐进加载 Log。
186. 作为大型仓库用户，我希望 Diff、Blame 和 File History 按需加载并可取消。
187. 作为暂时隐藏 Git 页面的用户，我希望后台降低只读刷新频率，但不取消正在执行的命令。
188. 作为设置应用的用户，我希望配置 Git 可执行文件、自动 Fetch、通用 Diff 偏好、通用确认和 Snapshot 保留策略。
189. 作为设置工作区的用户，我希望配置 Changelist/Staging、提交前命令、受保护分支和同步多 Root 操作。
190. 作为使用标准 Git 配置的用户，我希望 Remotes、Upstream 和 Root 级配置继续存储在 Git 配置中。
191. 作为使用 Breath 元数据的用户，我希望 Changelists、Shelves、提交草稿、选择、过滤和布局按工作区持久化。
192. 作为键盘用户，我希望 Git 页面在焦点位于 Git 工作台时采用 JetBrains macOS Git 快捷键语义。
193. 作为终端用户，我希望终端保持 Breath 既有快捷键，不被 Git 页面局部快捷键抢占。
194. 作为全局快捷键用户，我希望只有无歧义的打开 Git、Commit 和 Push 等命令可以配置为全局。
195. 作为自定义快捷键用户，我希望所有 Git 命令在设置的 Shortcuts 页面中可见、可修改。
196. 作为遇到快捷键冲突的用户，我希望设置页显示冲突命令及其作用域。
197. 作为学习快捷键的用户，我希望菜单项和工具提示展示当前生效快捷键。
198. 作为中文用户，我希望首次交付即完整支持简体中文。
199. 作为英文用户，我希望首次交付即完整支持英文。
200. 作为查看 Git 原始数据的用户，我希望 Commit Message、分支名、路径和原始命令输出保持原文。
201. 作为遇到已知错误的用户，我希望 Breath 提供本地化解释，同时保留完整原始 Git 错误以便排查。
202. 作为使用行业术语的用户，我接受 Rebase、Cherry-pick 等术语按产品词汇表保留或采用行业常见译法。
203. 作为 VoiceOver 用户，我希望可以识别和导航工具栏、树、Graph、Diff 行、状态和操作按钮。
204. 作为 VoiceOver 用户，我希望 Commit Graph 提供按时间和拓扑描述的线性替代表示。
205. 作为只使用键盘的用户，我希望完成从选择变更、审阅 Diff、填写消息到 Commit 的完整流程。
206. 作为使用增强对比度或减少动态效果的用户，我希望 Git 页面遵循系统辅助功能设置。
207. 作为调整应用字体的用户，我希望 Git 树、Log、Diff 和 Console 使用可读且一致的字体缩放。
208. 作为 Breath 用户，我希望所有本文确认能力完成并通过验收后，Git 工作台才被视为首次交付完成。

## Implementation Decisions

- 新建独立的 Git 工作台领域与用例模块，由 Breath App Shell 负责导航和绑定当前选中工作会话的工作区。该模块不得依赖 Agent、终端或任务领域。
- App Shell 只把稳定的 Workspace 标识和路径传给 Git 工作台。Git 工作台的页面状态、命令队列和持久化元数据均按 Workspace 隔离。
- 左侧底栏入口顺序固定为 Git 在任务视图左侧。无当前工作会话时入口禁用，但不隐藏。
- Git 页面使用单一三列工作台，而不是 Commit 与 Log 互斥标签页。分隔尺寸、折叠状态、过滤器和选择按 Workspace 保存。
- 右侧详情区采用“最后交互对象”规则，并为 Local Changes 与 Commit History 分别保存导航状态。
- Git CLI 是唯一 Git 执行后端。不得引入 libgit2、JGit 或自行实现 Git 对象数据库。
- 应用设置保存 Git 可执行路径。未配置时按系统规则探测；启动和路径变更时读取 Git 版本与能力矩阵。
- 所有 Git 调用通过统一进程执行接口完成。接口必须支持流式标准输出与错误、环境控制、可取消的只读命令、不可强杀的认证交互和脱敏记录。
- 提供受控 Askpass/Credential Broker，把用户名、密码、Token、SSH Passphrase 和 Host Key 确认请求转换为原生 Breath 对话框。秘密只存在于完成当前进程所需的内存中。
- Console 记录展示用命令时必须对 URL 凭证、认证 Header、Askpass 数据、秘密环境变量和交互输入进行脱敏。
- Git CLI 继承用户正常的 Git 配置、Hooks、签名、Credential Helper、SSH Agent、Git LFS 和必要环境；只注入实现 Breath 交互所需的最小环境。
- 每个 Git Root 拥有独立的写操作串行队列。只读查询可以并行，但必须避免用过期查询覆盖较新的写操作结果。
- 不同 Git Root 的队列可以并行。跨 Root 用例由协调器提交多个 Root 子操作并汇总结果。
- 跨 Root Commit 明确产生多个独立 Commit。执行前展示计划；发生部分失败时保留成功结果并呈现恢复建议，不伪造原子性。
- Checkout、Merge、Rebase、Reset、Push 等状态变更默认需要单 Root 上下文。
- 同步多 Root 分支操作是工作区级显式配置和显式动作。每次执行仍需展示 Root 计划；部分失败不自动回滚。
- Git Root 发现覆盖工作区目录本身、其后代中的独立仓库以及可能位于工作区父目录的仓库。
- 对工作区之外的父 Git Root 必须保存用户显式授权；未授权前只展示发现结果，不读取或修改工作区之外的仓库内容。
- Submodule 通过 Git 元数据识别，不按普通嵌套 Root 递归处理。进入 Submodule 后可建立独立 Root 上下文。
- Repository Snapshot 是 UI 的只读投影，包含 HEAD、Refs、状态、Index、进行中操作、Submodule、LFS 能力和必要统计。Git 与磁盘永远是事实来源。
- 使用文件系统事件监听工作树和 `.git` 相关状态，事件经合并后触发最小必要查询。任何用户操作后也要主动刷新受影响快照。
- 不自动删除 `index.lock`，不猜测外部进程是否死亡。展示 Git 原始错误、锁路径和刷新动作。
- 进行中的 Merge、Rebase、Cherry-pick 和 Revert 通过 Git 状态文件及 Git 命令检测，并投影为统一 Sequenced Operation 状态。
- Sequenced Operation 状态只暴露当前合法的 Continue、Skip、Abort 和冲突解决动作，其他不兼容写操作禁用。
- 默认工作流为 Changelist。工作区级设置可以切换为 Staging Area，两种 UI 不同时呈现。
- Changelist 是 Breath 工作区元数据，不等同于 Git Index。元数据至少关联 Root、路径、变更片段身份、顺序和用户命名。
- Hunk/行归属使用可重算的补丁上下文与稳定指纹。外部修改后无法唯一匹配的片段进入待确认状态，不能静默移动到其他 Changelist 或进入提交。
- Changelist 提交必须只提交选择内容，并保持未选择工作树修改和用户已有 Index 状态。实现可使用临时 Index 或等价隔离机制，但不得通过破坏再重建用户 Index 来掩盖失败。
- Staging 模式直接读取和写入真实 Git Index。HEAD、Staged、Local 三方编辑必须以原子写入方式更新 Index，并在失败后重新读取真实状态。
- Changelist 与 Staging 切换只改变当前交互模型；Changelist 元数据始终保留。切回时基于当前真实 Diff 重新关联。
- Commit Draft 按 Workspace 与当前 Changelist 或 Staging 上下文保存；成功 Commit 后仅清除实际消费的草稿。
- Commit Template 由 Git CLI 和仓库配置解析，不复制 Git 的 Template 查找逻辑。
- Commit Hook 默认运行。跳过 Hook 必须是本次 Commit 的显式选择，并在确认中标明影响。
- 工作区提交前命令按配置顺序运行，默认任一非零退出即阻止 Commit。输出进入同一操作详情并执行脱敏。
- Push 先构建可审阅的 Push Plan，包含 Root、Remote、Refspec、Outgoing Commits、文件、Tags 和是否使用 Force-with-lease。
- 所有覆盖式 Push 只允许使用 `--force-with-lease`。产品 UI、命令构造和快捷操作中不得出现无租约 `--force`。
- 受保护分支默认包含 main 和 master，支持工作区级模式。保护检查必须发生在 Breath 动作层和最终命令提交前两处。
- 受保护分支规则阻止 Force-with-lease、Drop/Edit 已发布历史及其他已确认的危险重写；无法获得托管平台规则时不得声称同步了服务器保护策略。
- Pull/Update 策略支持 Merge 与 Rebase，并按 Workspace/Root 记录用户选择。Push Rejected 流程复用同一策略。
- Branch、Tag、Remote 和 Upstream 修改全部通过 Git CLI 完成，结果通过重新读取 Refs 验证。
- Commit Graph 使用可分页数据源和虚拟化视图。初次进入页面不得等待完整历史加载。
- All Repositories Log 以 Root 为不可丢失的身份维度，可按时间聚合显示，但不得把不同仓库的图拓扑拼接成一张虚假图。
- File History、Blame 和 Commit Diff 按需加载，支持取消和缓存；工作树或 Ref 变化后按对象版本失效。
- Diff 领域模型统一支持 Working Tree、Index、Commit、Merge 三方和 Snapshot 来源。
- 文本 Diff 支持 Side-by-side、Unified、空白策略、搜索、折叠、行选择与可访问性语义。
- 编辑 Working Tree Diff 直接以安全文件写入方式更新磁盘。编辑 Staged Diff 直接更新 Index。UI 不保存一份脱离磁盘的“待写入版本”。
- 二进制和超大文件由能力检测决定是否提供系统预览、元数据或外部打开；默认不自动加载完整文本或生成昂贵 Diff。
- Rollback 文件、Hunk 和行前必须重新验证目标补丁仍适用于当前文件，避免基于陈旧 Diff 覆盖外部修改。
- Git Safety Snapshot 是 Breath 发起高风险操作前的 Best-effort 本地恢复点，不是 Git Commit、Stash 或连续 Local History。
- Snapshot 默认覆盖 Rollback、Checkout、Reset、Merge、Rebase、Stash Apply 及同等级可能覆盖工作树或 Index 的操作。
- Snapshot 数据存入应用缓存区域；元数据记录 Workspace、Root、动作、时间、基线和补丁对象。缓存可受系统磁盘清理影响。
- Snapshot 默认保留最近 5 个发生过修改的工作日。应用设置允许调整；0 表示禁用。
- Snapshot 创建、读取或清理失败只产生非阻塞警告，不阻止原 Git 操作。
- Snapshot 仅对 Breath 已知且即将影响的状态负责，不监听并记录所有终端、Agent 或外部工具修改。
- Git Stash 完全通过 Git CLI 管理，并保持与其他 Git 客户端互操作。
- Shelf 是 Breath Workspace 元数据和补丁内容，支持部分应用、重复应用、导入和导出。Shelf 不写入 Git Stash Refs。
- Stash 与 Shelf 可以合并或分开显示，但模型、动作名称和存储来源始终明确。
- Merge Tool 使用统一三方合并模型：两侧输入、Base、Result、未解决块和已解决状态。保存 Result 后再由 Git 标记解决。
- Merge/Rebase/Cherry-pick/Revert 的 Continue、Skip、Abort 必须调用对应 Git 命令，而不是直接删除状态文件。
- Remote 操作进度进入跨工作区 Operation Registry。页面销毁或 Workspace 切换不销毁 Operation。
- Operation Registry 区分只读、写入、等待认证、等待用户确认、运行、成功、失败和可正常取消状态。
- 应用退出时立即取消可取消的只读加载。存在写操作时进入退出协调：等待完成，或由用户请求命令支持的正常取消；不直接发送强制终止。
- 冲突等持久 Git 状态不视为后台运行命令，因此不阻止退出；下次启动从仓库重新发现。
- Console 按 Workspace 保存最近 7 天或 500 条记录，以先达到的上限为准。用户可清空或禁用持久化。
- Console 记录命令显示文本、开始/结束时间、退出状态和脱敏输出，不保存交互秘密或完整秘密环境。
- 自动 Fetch 默认 20 分钟。调度按 Root 去重，应用隐藏或页面不活跃时可降低频率。
- 无仓库空状态提供显式 Init 和 Clone。Init 从不自动执行；Clone 只允许新建或确认安全的空目录。
- Clone 成功后通过现有 Workspace 管理能力加入 Breath，不能覆盖非空工作区。
- Git LFS 能力通过 `git lfs` 探测。存在时使用标准 CLI 查看 Pointer、Fetch/Pull 对象和 Locks；不存在时只展示能力缺失。
- Breath 不安装 Git、Git LFS、Credential Helper、SSH 工具或签名工具。
- 应用级设置包括 Git 可执行文件、自动 Fetch、通用 Diff 偏好、通用确认、Console 持久化和 Snapshot 保留。
- 工作区级设置包括 Changelist/Staging、提交前命令、受保护分支、同步多 Root 操作、布局和交互状态。
- Root 级 Remotes、Upstream、Hooks、签名和其他 Git 配置继续由 Git 配置保存。
- Breath 持久化层保存 Changelists、Shelves、Commit Draft、页面布局、选择、过滤、用户授权、操作记录索引和相关工作区配置；不得保存认证秘密。
- 数据库迁移必须向后兼容已有 Breath 数据。Git 元数据损坏时应隔离失败记录并允许重新读取仓库，而不是阻止应用启动。
- Git 工作台快捷键按 Focus Scope 路由。Git 页面局部命令仅在 Git 工作台获得焦点时生效。
- Terminal 保持现有快捷键优先级。全局只开放明确的 Open Git、Commit、Push 等命令。
- 所有 Git 命令注册到统一快捷键目录，并在设置页显示默认值、用户覆盖、作用域和冲突。
- 默认键位以 JetBrains macOS Git 工作流为参考，但必须解决与 Breath 现有快捷键和 macOS 系统键位的冲突。
- 所有 Breath 自有文案和已知错误解释必须提供简体中文与英文。Git 原始数据和原始错误保留原文。
- Git Graph 必须同时提供机器可读的线性替代表达；Diff 行、状态、按钮和树节点必须有稳定可访问性标签和值。
- 页面必须支持 VoiceOver、完整键盘路径、增强对比度、减少动态效果和应用字体设置。
- 首次交付门禁以本文整体为单位。可以在开发阶段使用内部 Feature Flag 分步集成，但不能把未完成的已确认能力作为公开首版之后的可选增强。

## Testing Decisions

- 最高价值测试 Seam 是“Git 工作台用例层”：测试通过稳定服务接口选择 Workspace/Root、读取 Snapshot、提交操作、响应确认或认证请求，并观察操作结果与新的真实仓库状态。
- 用例层测试优先使用临时目录中的真实 Git 仓库和实际 Git CLI，不把核心行为建立在大量模拟命令返回值之上。
- 测试仓库使用本地 Bare Remote 验证 Fetch、Pull、Push、Force-with-lease、Rejected Push、Remote Branch、Tag 和多客户端竞争，不依赖公网。
- 测试接口应暴露 Repository Snapshot、Operation 状态流、交互请求、Console 记录和持久化元数据，从而能在 UI 之下覆盖完整工作流。
- 只在认证输入、长时间运行、信号处理、特定版本能力和难以稳定构造的系统错误处使用可控进程替身。
- 不把精确 Git 参数序列作为所有测试的主要断言；优先断言用户可见结果和真实仓库状态。
- 对安全契约使用精确命令断言，包括永不生成无租约 `--force`、不自动删除 `index.lock`、秘密不进入参数展示或 Console。
- 沿用现有临时真实仓库测试模式，扩展当前 Git 状态、Diff 读取和 Diff 展示测试，而不是建立第二套不一致的仓库 Fixture。
- 单 Root 基线测试覆盖仓库发现、当前分支、未跟踪/修改/删除/重命名、Index、Refs 和手动刷新。
- 父目录 Root 测试覆盖未授权只发现、显式授权、权限撤销和工作区外路径警告。
- Multi-root 测试覆盖 All Repositories Changes/Log 聚合、来源标识、单 Root 操作约束和独立并发。
- 跨 Root Commit 测试覆盖计划、每 Root 独立 Commit、部分失败和不伪造回滚。
- 同步分支操作测试覆盖默认关闭、显式开启、执行计划、部分失败和回退建议。
- Changelist 测试覆盖文件/Hunk/行分组、移动、重命名、删除、默认列表和独立提交。
- Changelist 外部变更测试覆盖上下文可重映射、歧义标记和禁止静默误提交。
- Changelist Commit 测试必须验证未选工作树修改和已有真实 Index 内容保持不变。
- Staging 测试覆盖文件/Hunk/行 Stage/Unstage，以及 HEAD、Staged、Local 三方编辑后真实 Index 内容。
- 工作流切换测试覆盖 Changelist 元数据保留、切回重映射和无法映射片段提示。
- Commit 测试覆盖 Template、最近消息、Draft 恢复、Commit、Commit and Push、Amend、Unversioned 和部分提交。
- Hook 与提交前命令测试覆盖默认执行、显式跳过、失败阻止、重试、输出脱敏和有序执行。
- Branch 测试覆盖创建、Checkout、Checkout and Update、重命名、删除、Upstream、Remote Branch 和 Tags。
- Log 测试覆盖 Graph 拓扑、Merge Commit、Refs 装饰、分页、过滤、Go to Hash/Branch/Tag 和多 Root 来源。
- History 操作测试覆盖 Merge、普通/Interactive Rebase、Cherry-pick、Revert、Undo Last Commit、各类 Reset、Fixup、Squash、Drop、Edit 和 Push to Commit。
- Interactive Rebase 测试应使用可控 Sequence Editor 集成，最终断言真实 Commit 图。
- Protected Branch 测试覆盖 main/master 默认规则、自定义模式、危险动作禁用和最终命令层二次保护。
- Push 测试覆盖审阅计划、不同 Refspec、Tags、Rejected Push、Merge/Rebase 选择、记忆策略和 Force-with-lease 竞争失败。
- 冲突测试用真实仓库构造 Merge、Rebase、Cherry-pick 和 Revert 冲突，覆盖 Continue、Skip、Abort 和重启恢复。
- Merge Tool 模型测试覆盖 Base/两侧/Result、无冲突块自动应用、逐块接受、手工编辑和未解决块门禁。
- Diff 测试覆盖 Side-by-side、Unified、空白选项、折叠、搜索、二进制、大文件、Working Tree 编辑和 Index 编辑。
- Rollback 测试覆盖文件/Hunk/行、陈旧补丁检测、确认门禁和最终磁盘状态。
- Git Safety Snapshot 测试覆盖触发动作、文件/片段恢复、默认 5 个修改工作日、配置为 0、磁盘清理和创建失败不阻塞。
- Snapshot 测试必须证明外部修改不会被产品误宣称为已完整记录的 Local History。
- Stash 测试覆盖标准互操作：Breath 创建的 Stash 能被 Git CLI 看到，CLI 创建的 Stash 能被 Breath 看到。
- Shelf 测试覆盖文件/Hunk/行、部分恢复、重复应用、删除、导入/导出 Patch 和工作区隔离。
- Credential 测试使用受控 Helper/Askpass 程序覆盖 HTTPS、SSH Passphrase、Host Key 确认和 Helper 持久化边界。
- 安全测试扫描 Console、持久化数据库和测试日志，确保 Token、Password、Passphrase 和秘密环境变量不存在。
- Git 可执行文件测试覆盖自动探测、自定义路径、Test、无效路径、旧版本和条件能力隐藏。
- 签名测试使用隔离的测试签名配置或可控签名程序，验证 Git 的成功与失败结果被完整呈现。
- 并发测试覆盖单 Root 写操作串行、不同 Root 并行、只读结果版本化和外部 Git 修改。
- `index.lock` 测试覆盖原始错误展示、不删除锁、锁解除后刷新恢复。
- 生命周期测试覆盖关闭页面、切换 Workspace、应用退出时取消只读、等待写操作和正常取消请求。
- Console 测试覆盖跨重启保留、7 天/500 条裁剪、清空、禁用持久化、运行状态和脱敏。
- Init/Clone 测试覆盖显式动作、空目录要求、非空目录拒绝和 Clone 后加入 Workspace。
- Submodule 测试覆盖识别、父指针变更、脏状态、Init/Update/Sync、进入独立 Root 和不参与同步 Root 传播。
- Git LFS 基础测试覆盖未安装能力检测。具备 Git LFS 的 CI Lane 额外覆盖 Pointer、对象 Fetch/Pull 和 Locks。
- 性能测试使用大型生成仓库验证 Changes/Branch 先显示、Log 分页虚拟化、Diff/Blame 可取消和事件合并。
- 持久化测试沿用现有数据库 Repository 与迁移测试模式，覆盖 Changelists、Shelves、Draft、布局、授权、Console 索引和设置。
- App Shell 测试覆盖 Git 按钮位置、无会话禁用、工作区绑定、跨工作区切换、运行徽标和跳转。
- 快捷键测试覆盖默认 JetBrains macOS 映射、Focus Scope、Terminal 不受影响、设置页展示、修改和冲突提示。
- 本地化测试覆盖所有新增 Breath 文案的简体中文和英文键值完整性，并验证原始 Git 数据不被翻译。
- 可访问性自动化测试覆盖主要控件标签、值、焦点顺序、状态非颜色表达和无鼠标 Commit 流程。
- VoiceOver 的 Graph 线性替代表达、三栏 Merge、复杂 Diff 导航和增强对比度需要人工辅助功能验收。
- UI 视觉验收重点检查三列布局、分隔调整、信息密度、Graph/状态/Diff 语义色和 Breath 原生 macOS 一致性，不要求 JetBrains 像素级截图匹配。
- 首次发布验收清单必须逐项映射本文所有 User Story。任何已确认能力未完成时，Git 工作台不得标记为首次交付完成。

## Out of Scope

- Git Worktree 的创建、删除、切换、列表、锁定、清理或任何专用 Worktree 工作流。
- GitHub Pull Request、GitLab Merge Request、Bitbucket Pull Request 等代码托管平台评审能力。
- GitHub、GitLab 等托管平台账号登录、平台 Issues、CI 状态、Review、Checks 或服务器分支保护规则同步。
- 把 Git 操作与 Agent 上下文、Agent 任务、Agent 生命周期、终端 Pane 或工作会话执行状态结合。
- 自行实现或内置 Git 对象数据库、libgit2、JGit 或自定义 Git 协议栈。
- 自动安装 Git、Git LFS、Credential Helper、SSH、GPG 或其他系统工具。
- 完整记录终端、Agent 和外部编辑器所有文件修改的连续 Local History。
- 自动创建、删除或可视化编辑 `.gitmodules` 的专用向导。
- 托管平台账号级的 Git LFS Lock 管理。
- 对 JetBrains UI 的像素级复制。

## Further Notes

- 本 PRD 采用项目的本地 Markdown Issue Tracker 规范，状态为 `ready-for-agent`。
- 产品术语以项目领域词汇表中的 Git Workbench、Git Root、Changelist、Git Staging Area、Git Safety Snapshot、Git Stash 和 Shelf 为准。
- 关键架构与安全边界由 ADR-0024 至 ADR-0031 记录：Agent 解耦、多 Root、Changelist/Staging、Git CLI 后端、安全快照、Git 事实来源与并发、受保护分支、后台操作与退出协调。
- 本需求规模显著大于单个实现票。进入开发前应按端到端 Tracer Bullet 拆分为可独立领取、明确依赖和验收 Seam 的实施 Issues，但拆分不得改变“所有已确认能力完成后才算首次交付”的发布门禁。
- JetBrains 对齐指行为、信息架构和用户预期对齐。若 JetBrains 在实现细节上依赖其 IDE 专属能力，而 Breath 没有等价语义，应优先保持 Git 结果正确、用户可理解和 Breath 模块边界清晰。
- Git 原始错误必须始终可查看。本地化解释用于帮助用户，不得替换或截断排障所需的原始信息。
- 所有高风险动作都应遵循“明确 Root、明确 Branch、明确影响、确认后执行、结果可追踪”的统一交互原则。
