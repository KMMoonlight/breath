# 打开当前工作区的单 Root Git 工作台

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

在左侧底栏任务视图按钮左侧提供 Git 入口，使用当前选中工作会话所属工作区发现一个 Git Root，并通过用户配置或自动发现的 Git CLI 打开完整 Git 页面骨架。没有选中工作会话时入口保持可见但禁用。

## Acceptance criteria

- [x] Git 入口位于任务视图按钮左侧，并在无当前工作会话时禁用且提供本地化帮助
- [x] 点击入口后右侧进入 Git 工作台，左侧栏保持可用
- [x] Git 工作台目标随当前选中工作会话所属工作区切换，同工作区切换会话不会重建状态
- [x] 单 Root 工作区显示 Root、当前分支和基础工作树状态
- [x] 设置中可自动发现、指定并测试 Git 可执行文件，且显示版本或错误
- [x] Git 工作台不读取 Agent、终端 Pane 或任务状态
- [x] 行为通过真实临时 Git 仓库和 App Shell 导航测试

## Blocked by

None - can start immediately
