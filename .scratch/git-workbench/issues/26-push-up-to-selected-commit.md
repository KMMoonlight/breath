# 只 Push 到选中的 Commit

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

从 Commit Graph 选择历史中的 Commit 构建受审阅的 Push Plan，只更新远程到该提交并遵守分支保护与 Force-with-lease。

## Acceptance criteria

- [x] 仅允许选择当前可达历史中的有效 Commit
- [x] Push Plan 清楚展示目标 Remote、Branch 和截止 Commit
- [x] Outgoing Commits、文件与 Diff 与实际 Refspec 一致
- [x] 受保护分支与 Force-with-lease 规则完整生效
- [x] 成功或拒绝结果刷新 Graph、Refs 和 Console
- [x] 本地 Bare Remote 测试覆盖正常与竞争拒绝

## Blocked by

- [16 浏览分页 Commit Graph 与提交详情](16-browse-paged-commit-graph.md)
- [19 审阅并执行 Pull、Push 和自动 Fetch](19-review-and-run-pull-push-auto-fetch.md)
- [20 保护主分支并只允许 Force-with-lease](20-protect-branches-and-force-with-lease.md)
