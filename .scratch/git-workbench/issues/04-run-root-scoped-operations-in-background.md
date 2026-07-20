# 让 Git 操作跨页面运行并按 Root 排队

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

建立跨工作区 Git Operation Registry，同一 Git Root 的写操作串行、不同 Root 可并行，并让操作在离开页面或切换工作区后继续运行。

## Acceptance criteria

- [x] 同一 Root 的 Breath 写操作严格串行，不同 Root 可以并行
- [x] 操作状态覆盖等待、运行、认证、确认、成功、失败和正常取消
- [x] 切换页面、会话或工作区不取消进行中的 Git 命令
- [x] Git 入口显示跨工作区运行和失败徽标，并可跳转到操作来源
- [x] Breath 不接管或终止外部 Git 进程
- [x] 应用退出取消只读加载，并等待写操作完成或接受显式正常取消
- [x] 队列、跨页面生命周期和退出协调通过用例测试

## Blocked by

- [01 打开当前工作区的单 Root Git 工作台](01-open-current-workspace-git-workbench.md)
- [03 让仓库快照持续反映真实 Git 状态](03-refresh-authoritative-repository-snapshots.md)
