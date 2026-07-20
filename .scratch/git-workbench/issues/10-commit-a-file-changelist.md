# 通过文件级 Changelist 完成首次 Commit

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

提供默认 Changelist 工作流，让用户组织文件、保存提交草稿并从真实仓库完成一次可审阅的 Commit。

## Acceptance criteria

- [x] 默认 Changelist 可创建、重命名、删除和设置默认项
- [x] 完整文件和未跟踪文件可移动到 Changelist
- [x] 提交草稿按工作区和 Changelist 保存并跨重启恢复
- [x] 提交计划明确展示 Root、文件和消息
- [x] Commit 只消费所选文件，其他工作树变更保持不变
- [x] 成功后刷新真实仓库并清除实际消费的草稿
- [x] 用例测试通过真实仓库完成文件级 Commit

## Blocked by

- [02 恢复三列 Git 页面布局与浏览状态](02-restore-three-column-workbench-state.md)
- [04 让 Git 操作跨页面运行并按 Root 排队](04-run-root-scoped-operations-in-background.md)
- [08 使用完整 Diff 审阅本地变更](08-review-local-changes-with-full-diff.md)
