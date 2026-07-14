# 处理不可用和被移除的工作区

Status: implemented

## Parent

[Breath v1 PRD](../spec.md)

## What to build

处理规范化目录重复、目录不可用和工作区移除。用户确认移除后停止相关终端并永久删除 Breath 元数据，但不重新定位或修改项目目录。

## Acceptance criteria

- [x] 同一规范化目录无法重复添加
- [x] 目录不可用时保留记录并提示移除，不自动删除或寻找新位置
- [x] 取消移除不会停止进程或改变元数据
- [x] 确认移除会停止所有相关终端并删除 Breath 元数据
- [x] 项目目录和文件始终不被修改

## Blocked by

- [05 正常退出并按需恢复工作会话](05-clean-exit-and-lazy-restore.md)
