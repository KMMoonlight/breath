# 安全执行 Undo Last Commit 与 Reset

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

提供 Undo Last Commit 及 Soft、Mixed、Hard、Keep Reset，在执行前创建 Snapshot、展示影响并遵守受保护分支规则。

## Acceptance criteria

- [x] Undo Last Commit 明确让用户选择修改保留方式
- [x] 支持 Soft、Mixed、Hard 和 Keep Reset
- [x] 执行前展示 Root、分支、目标 Commit 和将受影响的工作树/Index
- [x] 高风险模式执行前尽力创建 Git Safety Snapshot
- [x] 受保护分支和已发布历史规则得到执行
- [x] 最终 HEAD、Index、工作树和 Snapshot 通过真实仓库测试

## Blocked by

- [09 编辑和回滚工作树并创建 Git Safety Snapshot](09-edit-rollback-and-snapshot-working-tree.md)
- [16 浏览分页 Commit Graph 与提交详情](16-browse-paged-commit-graph.md)
- [20 保护主分支并只允许 Force-with-lease](20-protect-branches-and-force-with-lease.md)
