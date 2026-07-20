# 跨多个 Git Root 分别 Commit 并呈现部分结果

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

在 All Repositories 中选择多个 Root 的变更，先展示每 Root 独立 Commit 计划，再按 Root 执行并呈现部分成功边界。

## Acceptance criteria

- [x] 计划按 Root 列出 Changelist/Staged 内容、消息和检查
- [x] 每个 Root 产生普通独立 Git Commit
- [x] 不声称跨 Root 原子性
- [x] 某 Root 失败时保留已成功 Commit 并逐 Root 展示结果
- [x] 不自动回滚成功 Root，只提供明确恢复建议
- [x] 不同 Root 可并行，但单 Root 写队列仍串行
- [x] 真实多仓库测试覆盖全部成功和部分失败

## Blocked by

- [06 安全发现并聚合多个 Git Root](06-discover-and-aggregate-multiple-git-roots.md)
- [12 切换到原生 Staging 并编辑三方 Index](12-stage-files-hunks-and-lines.md)
- [13 运行 Commit Hooks 与工作区提交前检查](13-run-commit-hooks-and-workspace-checks.md)
- [14 支持 Commit 模板、历史消息、Amend 与签名](14-support-commit-templates-amend-and-signing.md)
