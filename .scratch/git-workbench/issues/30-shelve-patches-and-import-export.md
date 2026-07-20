# Shelve 局部修改并导入、导出 Patch

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

提供 Breath 本地 Shelf，把文件、Hunk、行或 Changelist 保存为可预览、可部分恢复、可重复应用的补丁集合。

## Acceptance criteria

- [x] 可从文件、Hunk、行或 Changelist 创建 Shelf
- [x] Shelf 支持预览、重命名、部分恢复、重复应用和删除
- [x] Shelf 与 Git Stash 的语义、来源和动作名称始终清楚
- [x] 用户可选择合并或分开显示 Stash 与 Shelf
- [x] 支持导入和导出标准 Patch
- [x] Shelf 按工作区持久化且不写入 Git Stash Refs
- [x] 补丁应用和工作区隔离通过测试

## Blocked by

- [08 使用完整 Diff 审阅本地变更](08-review-local-changes-with-full-diff.md)
- [11 按 Hunk 和行组织 Changelist 并隔离 Index](11-commit-changelist-hunks-and-lines.md)
