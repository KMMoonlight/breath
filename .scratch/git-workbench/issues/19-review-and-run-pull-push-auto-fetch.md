# 审阅并执行 Pull、Push 和自动 Fetch

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

提供 Push Plan 审阅、Pull/Update 策略、Rejected Push 恢复和可配置自动 Fetch。

## Acceptance criteria

- [x] Push 前审阅 Root、Remote、目标 Branch、Outgoing Commits、文件、Diff 和 Tags
- [x] Pull/Update 支持 Merge 与 Rebase 并可记住工作区偏好
- [x] Rejected Push 引导用户选择 Merge 或 Rebase 后重试
- [x] Commit and Push 在提交成功后进入同一 Push Plan
- [x] 自动 Fetch 默认 20 分钟并可调整或禁用
- [x] 页面隐藏时调度可降频且同一 Root 去重
- [x] 本地 Bare Remote 测试覆盖 Pull、Push、Tags、拒绝和自动 Fetch

## Blocked by

- [14 支持 Commit 模板、历史消息、Amend 与签名](14-support-commit-templates-amend-and-signing.md)
- [16 浏览分页 Commit Graph 与提交详情](16-browse-paged-commit-graph.md)
- [18 通过现有凭证安全 Fetch Remote](18-fetch-with-existing-credentials.md)
