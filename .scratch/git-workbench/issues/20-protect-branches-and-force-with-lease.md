# 保护主分支并只允许 Force-with-lease

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

默认保护 main/master，并在所有历史重写和覆盖式 Push 路径实施工作区规则与 Force-with-lease 安全门禁。

## Acceptance criteria

- [x] main 和 master 默认受保护，工作区可配置更多名称或模式
- [x] 受保护分支禁止 Force Push、Drop、Edit 和已发布历史重写
- [x] 允许覆盖式 Push 时只生成 `--force-with-lease`
- [x] UI、快捷操作和底层命令中不存在无租约 `--force`
- [x] 高风险确认显示 Root、分支和受影响 Commits
- [x] 保护检查在用例提交与最终命令执行前各进行一次
- [x] 并发更新 Remote 时 Force-with-lease 安全失败

## Blocked by

- [15 浏览和管理 Branch、Tag、Remote 与 Upstream](15-manage-branches-tags-remotes-and-upstreams.md)
- [18 通过现有凭证安全 Fetch Remote](18-fetch-with-existing-credentials.md)
- [19 审阅并执行 Pull、Push 和自动 Fetch](19-review-and-run-pull-push-auto-fetch.md)
