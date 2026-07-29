# Git 工作台首次交付验收矩阵

Status: implementation-complete-release-enabled-pending-manual-accessibility-acceptance

本矩阵按 PRD 顺序连续覆盖全部 208 条 User Stories。自动验收基于真实临时 Git 仓库、Swift Testing、源码契约、本地化资源检查和静态安全扫描。VoiceOver 辅助功能树与无鼠标复杂流程仍需在获得 macOS Accessibility 权限的机器上完成人工签字；根据完整功能打包要求，Release 构建现已默认包含 Git 工作台，人工辅助功能验收作为后续发布检查继续保留。

| PRD stories | Issues | 验收证据 | 状态 |
| --- | --- | --- | --- |
| Stories 1–12 | 01, 04, 05 | App Shell 入口顺序、当前会话工作区绑定、后台 Operation Registry、徽标与 Console 自动化测试；本地 Debug 构建截图确认 Git 位于 Tasks 左侧 | 自动通过 |
| Stories 13–22 | 02, 35 | 三列工作台、可拖动分隔、详情来源、状态文字、字体和辅助功能源码契约 | 自动通过；人工辅助功能待签字 |
| Stories 23–29 | 06 | 真实仓库 Root 发现、嵌套 Root、外部父 Root 授权、多 Root 图隔离测试 | 自动通过 |
| Stories 30–36 | 27, 28 | 多 Root 独立 Commit、部分成功、同步分支计划与 Submodule 排除用例 | 自动通过 |
| Stories 37–48 | 10, 11, 12 | Changelist 文件/Hunk/行选择、重映射歧义、Index 隔离真实仓库测试 | 自动通过 |
| Stories 49–54 | 12 | 文件/Hunk/行 Stage/Unstage、三方 Index 编辑与外部刷新测试 | 自动通过 |
| Stories 55–67 | 10, 13, 14 | Draft、Template、最近消息、Commit/Amend/Sign、Hooks 与提交前命令测试 | 自动通过 |
| Stories 68–78 | 15 | Branch、Tag、Remote、Upstream 查询及 mutation 后重读验证 | 自动通过 |
| Stories 79–85 | 16 | 真实拓扑、Refs 装饰、分页、复合过滤、详情与 Commit Diff 测试 | 自动通过 |
| Stories 86–87 | 17 | Rename-aware File History 与逐行 Blame 测试 | 自动通过 |
| Stories 88–101 | 20, 21, 22, 23, 24, 25, 26 | Merge/Rebase/Cherry-pick/Revert/Reset/Undo/Fixup/Interactive Rebase、保护分支与 Push cutoff 测试 | 自动通过 |
| Stories 102–109 | 18, 19, 20 | Push Plan、Outgoing Diff、Pull 策略、自动 Fetch、Askpass 与 force-with-lease 测试 | 自动通过 |
| Stories 110–117 | 21, 22, 23 | 冲突状态重发现、三方数据、逐块解决、Continue/Skip/Abort 测试 | 自动通过 |
| Stories 118–126 | 08, 09 | Unified/Side-by-side、导航、空白偏好、大文件降级、编辑与 Rollback/Snapshot 测试 | 自动通过 |
| Stories 127–135 | 09 | Safety Snapshot 创建、保留、比较、文件/片段恢复及失败不阻塞测试 | 自动通过 |
| Stories 136–142 | 29, 30 | 标准 Stash 互操作、Shelf 隔离、预览、重复应用、Import/Export Patch 测试 | 自动通过 |
| Stories 143–147 | 05, 18 | Credential Helper/Askpass 进程边界与 Console/持久化秘密扫描测试 | 自动通过 |
| Stories 148–152 | 01, 14, 32 | Git executable 探测/Test、版本能力、签名交互与 LFS 能力检测 | 自动通过 |
| Stories 153–169 | 03, 04, 05 | 文件事件节流、陈旧读取防护、Root 写串行、跨 Root 并行、退出协调、Console 留存测试 | 自动通过 |
| Stories 170–174 | 07 | 显式 Init、Clone、安全空目录和 Clone 后 Workspace 回调测试 | 自动通过 |
| Stories 175–179 | 31 | Submodule 识别、Init/Update/Sync、独立 Root 与传播排除测试 | 自动通过 |
| Stories 180–184 | 32 | Git LFS 探测、Pointer、Fetch/Pull 与 Locks 查询路径测试 | 自动通过 |
| Stories 185–191 | 02, 03, 16, 17, 19, 33 | Changes 优先、Log 分页、按需可取消查询、页面降频与设置/元数据持久化测试 | 自动通过 |
| Stories 192–197 | 33 | JetBrains macOS 默认快捷键、焦点 Scope、Terminal 隔离、设置冲突和命令面测试 | 自动通过 |
| Stories 198–202 | 34 | 简中/英文键集合、占位符、原始 Git 数据与错误保留检查 | 自动通过 |
| Stories 203–207 | 35 | 稳定 accessibility label、非颜色状态、Graph 线性拓扑描述、键盘命令面、Reduce Motion 与字体契约 | 自动通过；VoiceOver/无鼠标人工验收待签字 |
| Stories 208 | 36 | 本矩阵、36 Issue 门禁、完整回归与范围扫描 | 实现完成；Release 已启用，人工辅助功能验收待签字 |

## 自动验收记录

- 自动测试聚合结果：169 个测试中 168 个通过。`BreathAppTests` 中除 `WorkbenchEmptyStateTests` 外的 101 个测试全部通过，其余模块 66 个测试全部通过；该空状态套件自身的纯像素测试通过，原生 App 校验测试被当前机器的 Endpoint Security 在 LaunchServices 启动阶段以 SIGKILL 拒绝。Git 工作台新增测试套件全部通过。
- 全量 `swift test --disable-sandbox --quiet` 完成 169 项测试并仅报告上述 1 项既有原生 App 校验失败，因此完整套件门禁仍未签字。
- `swift build --disable-sandbox -c release`：通过；公开 Release 默认包含 Git 工作台。
- `plutil -lint`：简体中文与英文 `Localizable.strings` 均通过。
- 安全范围扫描：不存在裸 `--force` 命令；仅允许 `--force-with-lease`。Git 工作台源码不导入 `BreathAgents`，不包含 Git Worktree 命令或托管平台集成。
- 专项用例：真实临时仓库覆盖分页历史、特殊文件名与 Rename、冲突恢复、Interactive Rebase、跨 Root 并发与部分成功、stdout/stderr 隔离、凭证脱敏、退出时取消只读并等待写操作。

## 待完成人工验收

- 当前执行环境的 Orca runtime 启动后立即退出，`orca computer` 无法提供辅助功能树。
- `AXIsProcessTrusted()` 为 `false`，`osascript` 也被 macOS 拒绝辅助访问，因此无法在本轮代替人工完成 VoiceOver、Merge Tool、复杂 Diff 与全键盘流程签字。
- 当前机器的 Endpoint Security 会拒绝测试创建的临时 `BreathAppShellVerifier.app`；系统日志记录 `ES_AUTH_RESULT_DENY`，即使复制并 ad-hoc 签名临时 Bundle 也会在启动后被 SIGKILL。该环境限制阻止既有原生空状态校验完成。
- 以上不是未实现的产品代码，也不再阻止完整功能打包。获得辅助功能权限后仍应按 Issue 35 完成人工验收，并补充 Issue 35/36 的签字记录。
