# 运行 Commit Hooks 与工作区提交前检查

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

在 Commit 前按顺序运行工作区配置的 Shell 检查，并默认保留 Git 自身 Commit Hooks。

## Acceptance criteria

- [x] 工作区可配置格式化、Lint、类型检查和测试命令列表
- [x] 命令按顺序运行，任一非零退出默认阻止 Commit
- [x] 失败输出完整展示、经过脱敏并支持重试
- [x] Git Commit Hooks 默认运行
- [x] 跳过可跳过 Hook 必须是本次 Commit 的显式选择
- [x] 不提供伪 IDE Inspection 或 TODO 分析
- [x] 检查、Hook、失败与重试通过真实提交测试

## Blocked by

- [04 让 Git 操作跨页面运行并按 Root 排队](04-run-root-scoped-operations-in-background.md)
- [10 通过文件级 Changelist 完成首次 Commit](10-commit-a-file-changelist.md)
