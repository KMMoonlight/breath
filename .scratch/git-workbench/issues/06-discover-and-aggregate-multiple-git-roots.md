# 安全发现并聚合多个 Git Root

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

发现工作区内的独立 Git Root、嵌套仓库和可能位于父目录的 Root，并提供单 Root 与 All Repositories 聚合浏览。

## Acceptance criteria

- [x] 独立 Root 与嵌套仓库被识别并具有稳定身份
- [x] 父目录 Root 在未授权时只显示发现结果和工作区外警告
- [x] 用户显式授权后才允许读取或修改工作区外 Root
- [x] All Repositories Changes 按 Root 分组
- [x] All Repositories Log 保留每个 Commit 的 Root 来源且不伪造跨仓库图
- [x] 仓库状态变更操作默认要求一个明确 Root
- [x] 多 Root 与父目录授权通过真实仓库测试

## Blocked by

- [01 打开当前工作区的单 Root Git 工作台](01-open-current-workspace-git-workbench.md)
- [03 让仓库快照持续反映真实 Git 状态](03-refresh-authoritative-repository-snapshots.md)
