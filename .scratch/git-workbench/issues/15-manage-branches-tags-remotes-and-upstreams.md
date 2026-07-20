# 浏览和管理 Branch、Tag、Remote 与 Upstream

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

提供 JetBrains 风格的分支弹层和左侧树，浏览、搜索、收藏并管理本地/远程分支、Tags、Remotes 与 Upstream。

## Acceptance criteria

- [x] 展示本地分支、远程分支、Tags、当前分支和 Incoming/Outgoing
- [x] 支持搜索、前缀分组和收藏
- [x] 支持从当前 HEAD、选中分支或 Commit 创建分支
- [x] 支持 Checkout、Checkout and Update、重命名和删除
- [x] 支持设置/取消 Upstream 及查看、新增、编辑、删除 Remote
- [x] Root 级配置继续存入 Git 配置而非 Breath 元数据
- [x] 所有修改通过重新读取 Refs 验证

## Blocked by

- [04 让 Git 操作跨页面运行并按 Root 排队](04-run-root-scoped-operations-in-background.md)
- [06 安全发现并聚合多个 Git Root](06-discover-and-aggregate-multiple-git-roots.md)
