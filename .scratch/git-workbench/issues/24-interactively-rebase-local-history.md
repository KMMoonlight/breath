# 使用 Interactive Rebase 重写本地历史

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

提供可视化 Interactive Rebase 计划，支持重新排序、Reword、Squash、Fixup、Drop、Edit 以及把当前修改归入较早本地提交。

## Acceptance criteria

- [x] 用户可选择本地提交范围并审阅 Rebase 计划
- [x] 支持重新排序、Reword、Squash、Fixup、Drop 和 Edit
- [x] 支持把当前修改 Amend/Fixup 到选中的未发布 Commit
- [x] 受保护或已发布历史按规则阻止危险动作
- [x] 冲突复用 Rebase 序列操作和三方合并器
- [x] 可控 Sequence Editor 测试断言最终真实 Commit 图

## Blocked by

- [14 支持 Commit 模板、历史消息、Amend 与签名](14-support-commit-templates-amend-and-signing.md)
- [16 浏览分页 Commit Graph 与提交详情](16-browse-paged-commit-graph.md)
- [20 保护主分支并只允许 Force-with-lease](20-protect-branches-and-force-with-lease.md)
- [22 Rebase 分支并继续、跳过或中止冲突序列](22-rebase-and-resolve-sequenced-conflicts.md)
