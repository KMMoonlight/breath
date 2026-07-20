# 发现并聚合所有受支持 Agent 的 Skills

Status: implemented

## Parent

[Breath 全局 Skills 管理](../spec.md)

## What to build

把首条 Codex 路径扩展到 Breath 支持矩阵中的全部 Agent，并以实际目录内容聚合成统一清单。内容一致的跨 Agent 副本合并显示；同名但内容不同的 Skill 保持独立，通过说明、来源和真实路径自然区分，不添加“同名冲突”标签。

本切片覆盖 PRD User Stories 10–21、23、26–37、130。

## Acceptance criteria

- [x] Codex、Claude Code、Gemini CLI、GitHub Copilot CLI、Qwen Code、Cursor Agent、Factory Droid、OpenCode 和 Pi 都通过现有 Agent 支持注册表声明全局 Skill 能力，不维护第二份 Agent 名单
- [x] 每个 Agent 能解析自己的有效配置根和实际全局 Skill 目录，包括受支持的自定义配置根；路径无法确认、版本不兼容或 Agent 未安装时显示原因并禁止成为未来写入目标
- [x] 扫描以九个 Agent 目录中的真实普通目录为事实来源，不要求存在 Breath 安装记录，并能展示其他工具或手工安装的合法 Skill
- [x] 聚合身份使用 `name + 规范化内容摘要`；相同名称和内容的跨 Agent 副本合并为一行并列出 Agent
- [x] 同名不同内容的 Skill 分行展示各自 `description`、来源和路径，不显示额外的同名冲突标签
- [x] 内容摘要忽略不影响行为的文件系统噪声，但 Skill 文件、引用或资源变化会产生不同摘要
- [x] 页面支持按 Agent 和来源筛选，并在列表、汇总和详情中展示每个聚合项的 Agent 副本及解析后的真实路径
- [x] 文件清单、Finder 定位和窄窗口详情适用于所有受支持 Agent，而不是只适用于 Codex
- [x] 使用九类临时真实 Agent 根目录覆盖默认路径、自定义配置根、未安装和无法解析状态，并验证跨 Agent 聚合与同名分行行为
- [x] 支持矩阵契约测试遍历所有 Agent 描述符；以后新增受支持 Agent 但未声明完整 Skills 契约时测试失败

## Blocked by

- [添加 Skills 入口并展示 Codex Skills](01-open-skills-and-list-codex-skills.md)
