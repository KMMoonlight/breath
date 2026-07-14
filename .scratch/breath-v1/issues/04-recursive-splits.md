# 创建并持久化递归分屏布局

Status: implemented

## Parent

[Breath v1 PRD](../spec.md)

## What to build

在一个工作会话中交付横向、纵向和递归分屏。每个新终端窗格独立启动工作区根目录中的空 Shell，会话树在分屏后展示第三级，布局比例可以持久化。

## Acceptance criteria

- [x] 任意窗格可以横向或纵向等分并继续递归分屏
- [x] 用户可以拖动每层分隔线，方向、比例和稳定窗格 ID 可持久化往返
- [x] 每个新窗格拥有独立 cwd、进程和运行状态
- [x] 多窗格时会话树展示窗格节点，父工作会话不汇总状态
- [x] 活动窗格关闭前确认，最后一个窗格不能单独关闭

## Blocked by

- [03 管理多个工作会话并保持后台运行](03-multiple-work-sessions.md)
