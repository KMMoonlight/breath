# 将 Submodule 作为显式 Git Root 管理

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

在父仓库中识别 Submodule、指针变化和脏状态，并允许 Init、Update、Sync URL 或显式进入其独立 Root。

## Acceptance criteria

- [x] 父仓库清楚展示 Submodule、指针变化和脏状态
- [x] 支持 Init、Update 和 Sync URL
- [x] 用户可进入 Submodule 并作为独立 Git Root 操作
- [x] Submodule 不按普通嵌套目录递归提交
- [x] 同步多 Root 分支操作不传播到 Submodule
- [x] 不提供创建、删除或可视化编辑 `.gitmodules` 的专用向导
- [x] 真实 Submodule 仓库测试覆盖父子状态

## Blocked by

- [06 安全发现并聚合多个 Git Root](06-discover-and-aggregate-multiple-git-roots.md)
- [15 浏览和管理 Branch、Tag、Remote 与 Upstream](15-manage-branches-tags-remotes-and-upstreams.md)
- [18 通过现有凭证安全 Fetch Remote](18-fetch-with-existing-credentials.md)
