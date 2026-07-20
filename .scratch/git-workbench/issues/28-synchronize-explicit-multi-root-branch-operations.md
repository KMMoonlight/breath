# 显式同步多个 Root 的分支操作

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

提供默认关闭的工作区级同步分支能力，让用户显式选择多个 Root 执行 Checkout、Merge、Rebase、Reset 或 Push，并看见部分失败。

## Acceptance criteria

- [x] 同步多 Root 分支操作默认关闭且可在工作区设置开启
- [x] 每次执行前展示 Root、源分支、目标分支和顺序
- [x] Submodule 不自动参与传播
- [x] 每 Root 遵守受保护分支、Snapshot 和写队列规则
- [x] 部分失败不自动回滚，展示成功/失败 Root 和回退建议
- [x] 真实多仓库测试覆盖成功、缺失分支和中途失败

## Blocked by

- [06 安全发现并聚合多个 Git Root](06-discover-and-aggregate-multiple-git-roots.md)
- [15 浏览和管理 Branch、Tag、Remote 与 Upstream](15-manage-branches-tags-remotes-and-upstreams.md)
- [19 审阅并执行 Pull、Push 和自动 Fetch](19-review-and-run-pull-push-auto-fetch.md)
- [20 保护主分支并只允许 Force-with-lease](20-protect-branches-and-force-with-lease.md)
- [21 Merge 分支并完成三方冲突解决](21-merge-and-resolve-conflicts.md)
- [22 Rebase 分支并继续、跳过或中止冲突序列](22-rebase-and-resolve-sequenced-conflicts.md)
- [25 安全执行 Undo Last Commit 与 Reset](25-undo-last-commit-and-reset-safely.md)
