# 让仓库快照持续反映真实 Git 状态

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

以 Git CLI 和磁盘为事实来源维护仓库快照，在工作树、Index、Refs 和进行中操作变化后自动合并刷新，并允许用户手动刷新。

## Acceptance criteria

- [x] 快照包含 HEAD、分支、工作树、Index、Refs 和进行中 Git 状态
- [x] 文件系统变化触发节流合并后的最小必要刷新
- [x] 外部终端产生的 Git 变化能自动出现在工作台
- [x] 陈旧只读查询不能覆盖较新的仓库状态
- [x] `index.lock` 只展示原始错误和刷新动作，绝不自动删除
- [x] 隐藏 Git 页面时降低只读刷新频率但不停止状态正确性
- [x] 真实仓库测试覆盖自动刷新、手动刷新和外部修改

## Blocked by

- [01 打开当前工作区的单 Root Git 工作台](01-open-current-workspace-git-workbench.md)
