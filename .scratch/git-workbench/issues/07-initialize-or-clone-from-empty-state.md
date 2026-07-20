# 从 Git 空状态初始化或克隆仓库

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

为没有 Git Root 的工作区提供显式 Init 和 Clone 流程，并在 Clone 成功后把新目录加入 Breath Workspace。

## Acceptance criteria

- [x] 无仓库工作区展示安静、可操作的 Git 空状态
- [x] `git init` 只在用户明确选择的目录执行，绝不自动初始化
- [x] Clone 要求新目录或安全空目录，拒绝覆盖非空目录
- [x] Clone 进度和错误进入 Operation Registry 与 Console
- [x] Clone 成功后新目录自动加入 Breath Workspace
- [x] Init、Clone 和非空目录拒绝通过本地仓库测试

## Blocked by

- [01 打开当前工作区的单 Root Git 工作台](01-open-current-workspace-git-workbench.md)
- [04 让 Git 操作跨页面运行并按 Root 排队](04-run-root-scoped-operations-in-background.md)
