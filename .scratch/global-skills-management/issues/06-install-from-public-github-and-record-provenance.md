# 从公共 GitHub 仓库安装并记录来源

Status: implemented

## Parent

[Breath 全局 Skills 管理](../spec.md)

## What to build

允许用户输入公开 GitHub Repo、`owner/repo` 或 Skill 子目录来源，解析明确的分支、Tag 或 Commit，复用现有多 Skill 安装预览和原子写入流程。成功后只在 Breath SQLite 中保存可验证上游元数据；磁盘内容仍是是否安装的唯一事实来源。

本切片覆盖 PRD User Stories 47–54、93–100；其中 skills.sh 上游的实际接入由后续切片完成。

## Acceptance criteria

- [x] 在线来源接受公开 Repo URL、`owner/repo`、Repo 内 Skill 子目录及明确的分支、Tag 或 Commit，不提供整个 GitHub 搜索
- [x] 默认 Repo 解析并记录默认分支与实际 Commit，指定分支记录跟随分支，Tag 和 Commit 记录为固定引用
- [x] Repo 中可发现一个或多个候选 Skill，并复用候选多选、目标选择、强制预览、同名处理、原子写入和逐目标结果
- [x] 私有或需要认证的 Repo 显示首版不支持并建议改用 ZIP；Breath 不读取 GitHub Token、登录状态、SSH 或 Git credential
- [x] 成功安装记录至少包含 Agent、安装路径、Skill 身份、来源类型、Repo、来源相对位置、跟随或固定引用、实际 Commit、安装内容摘要和时间信息
- [x] 来源记录通过 SQLite migration 和 repository 持久化，Skill 完整内容只存在于各 Agent 真实目录，不写入 Breath 应用数据目录或 Skill sidecar
- [x] 对账发现目录已删除时立即移除列表项；安装数据库丢失或记录无法验证时，磁盘 Skill 仍展示但降级为来源未知
- [x] 路径与 Skill 身份仍匹配但内容摘要变化时标记为本地已修改并保留上游；路径被其他 Skill 占用或身份无法确认时不按名称猜测来源
- [x] 可以只读利用安全匹配的生态兼容清单恢复上游，但 Breath 不修改其他工具的清单或锁文件
- [x] GitHub 网络和解析失败只影响当前在线操作，不阻塞本地列表、ZIP 安装、诊断或卸载能力
- [x] 使用记录型或本地协议 Provider 以及临时真实目录覆盖 Repo 简写、子目录、默认分支、指定分支、Tag、Commit、404、私有来源、限流、部分安装和本地修改对账
- [x] SQLite 测试覆盖 schema migration、round trip、应用重启、记录存在但目录缺失以及删除数据库不影响实际 Skill

## Blocked by

- [同步外部变更并诊断异常 Skill](03-reconcile-external-changes-and-diagnose-invalid-skills.md)
- [批量安装 Skills 并处理同名覆盖](05-batch-install-skills-and-handle-name-replacement.md)
