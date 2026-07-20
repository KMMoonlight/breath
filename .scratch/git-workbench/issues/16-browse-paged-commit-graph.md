# 浏览分页 Commit Graph 与提交详情

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

在中列提供渐进加载、虚拟化的 Commit Graph，并在右侧展示提交详情、文件和相对父提交的 Diff。

## Acceptance criteria

- [x] Graph 展示分叉、合并、分支和 Tag 装饰
- [x] 首屏分页加载且不阻塞 Changes 与当前分支
- [x] 支持作者、时间、路径、分支、Root 和文本过滤
- [x] 支持跳转到 Hash、Branch 和 Tag
- [x] 提交详情包含作者、时间、父提交、完整消息、Refs 和文件
- [x] All Repositories 保留 Root 来源且不拼接虚假拓扑
- [x] 大型生成仓库验证分页和虚拟化

## Blocked by

- [02 恢复三列 Git 页面布局与浏览状态](02-restore-three-column-workbench-state.md)
- [03 让仓库快照持续反映真实 Git 状态](03-refresh-authoritative-repository-snapshots.md)
- [06 安全发现并聚合多个 Git Root](06-discover-and-aggregate-multiple-git-roots.md)
