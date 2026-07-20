# 恢复三列 Git 页面布局与浏览状态

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

提供同时容纳 Changes、Commit Graph、Diff/详情和底部 Console 的可调整三列工作台，并按工作区恢复布局、折叠、过滤和两类详情选择。

## Acceptance criteria

- [x] 顶部工具栏、左列、中列、右列和可折叠 Console 同时存在
- [x] 三列与 Console 分隔位置可调整并按工作区持久化
- [x] Local Changes 与 Commit History 分别保存选择、滚动和过滤状态
- [x] 右侧根据最后交互对象显示本地 Diff 或 Commit 详情并明确标识来源
- [x] 页面遵循 Breath 原生 macOS 风格及 JetBrains 信息架构
- [x] 布局恢复和详情路由通过工作台公开状态测试

## Blocked by

- [01 打开当前工作区的单 Root Git 工作台](01-open-current-workspace-git-workbench.md)
