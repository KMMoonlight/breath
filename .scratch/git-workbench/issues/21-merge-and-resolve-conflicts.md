# Merge 分支并完成三方冲突解决

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

从 Branch 或 Log 发起 Merge，在冲突时展示 Merge Conflicts 节点和可编辑三方合并器，并通过 Git Continue 或 Abort 完成流程。

## Acceptance criteria

- [x] Merge 前展示 Root、源分支、目标分支和受影响内容
- [x] Breath 与外部命令产生的 Merge 冲突都能被发现
- [x] 三方合并器展示两侧、Base、Result 和未解决块
- [x] 支持应用无冲突块、接受/忽略任一侧和手工编辑 Result
- [x] 未解决块阻止 Continue，保存后通过 Git 标记已解决
- [x] Continue 与 Abort 调用标准 Git 命令
- [x] 真实冲突仓库测试覆盖重启恢复

## Blocked by

- [09 编辑和回滚工作树并创建 Git Safety Snapshot](09-edit-rollback-and-snapshot-working-tree.md)
- [15 浏览和管理 Branch、Tag、Remote 与 Upstream](15-manage-branches-tags-remotes-and-upstreams.md)
- [16 浏览分页 Commit Graph 与提交详情](16-browse-paged-commit-graph.md)
- [20 保护主分支并只允许 Force-with-lease](20-protect-branches-and-force-with-lease.md)
