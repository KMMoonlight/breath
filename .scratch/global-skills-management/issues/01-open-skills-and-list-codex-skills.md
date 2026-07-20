# 添加 Skills 入口并展示 Codex Skills

Status: implemented

## Parent

[Breath 全局 Skills 管理](../spec.md)

## What to build

交付全局 Skills 管理的第一条完整路径：用户无需工作区即可从侧栏底部进入 Skills 页面，Breath 通过公开的全局 Skills 用例服务扫描 Codex 的实际全局 Skill 目录，并在原生列表和详情中展示可用内容。选择任一工作会话后，主内容区仍按既有规则返回终端。

本切片覆盖 PRD User Stories 1–9、22、24、29、33–35，并建立后续 Agent、安装、更新和卸载功能共用的最小服务边界。

## Acceptance criteria

- [x] 侧栏底部提供与任务视图相邻的 Skills 入口；入口不依赖当前工作区或工作会话，在无工作区状态下也能打开
- [x] Skills 页面属于全局主内容模式；用户选择任一工作会话后，主内容区切回该会话终端
- [x] Codex 的 Agent 描述能力可以判断是否已安装并解析有效配置根下的实际全局 Skill 目录，无法可靠解析时返回明确状态而不猜测写入位置
- [x] 公开的全局 Skills 用例服务从真实目录扫描合法 `SKILL.md`，读取 `name`、`description` 和文件清单，并在任何远程工作之前发布本地快照
- [x] 列表至少展示名称、说明、Codex、来源未知和更新不可用状态，并支持按 `name` 或 `description` 搜索及手动刷新
- [x] 详情可以查看完整 `description`、`SKILL.md`、文件清单和真实路径，并可在 Finder 中显示对应目录
- [x] 宽窗口使用列表与详情，窄窗口可进入独立详情页面，空状态保持安静且可操作
- [x] 新增入口、状态和操作具备完整键盘、VoiceOver、本地化和系统外观语义，状态不只依赖图标或颜色
- [x] 使用临时真实 Codex 用户根目录验证扫描、刷新和详情，通过 App Shell 测试验证无工作区可达及选择会话返回终端
- [x] 打开和浏览页面不会访问网络、启动 Agent、改变终端或工作会话，也不要求账户、后端、Node.js 或 `npx skills`

## Blocked by

None - can start immediately
