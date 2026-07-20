# Cherry-pick、Revert 并解决冲突

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

从 Commit Graph 对一个或多个提交执行 Cherry-pick、Revert 或应用选定修改，并复用序列操作与冲突解决体验。

## Acceptance criteria

- [x] 支持按选定顺序 Cherry-pick 一个或多个 Commit
- [x] 支持通过 Revert 生成反向 Commit
- [x] 支持把选中 Commit 的文件或部分修改应用到工作树
- [x] 冲突使用统一三方合并器
- [x] Cherry-pick/Revert 提供合法的 Continue、Skip、Abort
- [x] 应用重启后重新发现进行中状态
- [x] 真实仓库测试覆盖成功、冲突和恢复

## Blocked by

- [16 浏览分页 Commit Graph 与提交详情](16-browse-paged-commit-graph.md)
- [20 保护主分支并只允许 Force-with-lease](20-protect-branches-and-force-with-lease.md)
- [21 Merge 分支并完成三方冲突解决](21-merge-and-resolve-conflicts.md)
