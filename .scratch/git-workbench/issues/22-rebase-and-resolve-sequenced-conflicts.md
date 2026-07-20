# Rebase 分支并继续、跳过或中止冲突序列

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

提供普通 Rebase，并把进行中的 Rebase 建模为可恢复序列，复用三方冲突解决并提供 Continue、Skip、Abort。

## Acceptance criteria

- [x] Rebase 前展示 Root、源、目标和预计重放 Commits
- [x] Rebase 冲突进入统一 Merge Conflicts 与三方合并器
- [x] 仅展示当前状态合法的 Continue、Skip 和 Abort
- [x] 进行中 Rebase 时不兼容写操作禁用并解释原因
- [x] 应用退出不破坏 Rebase，下次启动重新发现
- [x] Continue、Skip、Abort 通过标准 Git 命令执行
- [x] 真实仓库测试覆盖成功、冲突、跳过、中止和恢复

## Blocked by

- [20 保护主分支并只允许 Force-with-lease](20-protect-branches-and-force-with-lease.md)
- [21 Merge 分支并完成三方冲突解决](21-merge-and-resolve-conflicts.md)
