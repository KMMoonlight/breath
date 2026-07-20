# 管理标准 Git Stash

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

通过标准 Git CLI 创建、预览、Apply、Pop 和 Drop Stash，并让 Breath 与其他 Git 客户端保持互操作。

## Acceptance criteria

- [x] 创建 Stash 支持消息、未跟踪文件和保留 Index 等选项
- [x] 列表展示标准 Git Stash Refs 和摘要
- [x] 用户可预览 Stash Diff
- [x] Apply、Pop 和 Drop 显示确认、结果和冲突状态
- [x] Stash Apply 前尽力创建 Git Safety Snapshot
- [x] CLI 创建的 Stash 可见，Breath 创建的 Stash 可被 CLI 使用

## Blocked by

- [04 让 Git 操作跨页面运行并按 Root 排队](04-run-root-scoped-operations-in-background.md)
- [09 编辑和回滚工作树并创建 Git Safety Snapshot](09-edit-rollback-and-snapshot-working-tree.md)
