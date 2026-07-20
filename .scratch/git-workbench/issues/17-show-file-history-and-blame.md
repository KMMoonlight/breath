# 按需查看 File History 与 Blame

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

从 Changes、Commit 文件和编辑器路径按需打开 File History 与 Blame，并允许从行跳回对应 Commit。

## Acceptance criteria

- [x] File History 展示路径相关提交并支持重命名历史
- [x] Blame 显示每行 Commit、作者和时间
- [x] 用户可以从 Blame 行跳到 Commit Graph 对应提交
- [x] 查询按需加载、可取消并按对象版本失效缓存
- [x] 大文件加载不会阻塞 Git 页面其他区域
- [x] 真实仓库测试覆盖重命名、历史和行归属

## Blocked by

- [08 使用完整 Diff 审阅本地变更](08-review-local-changes-with-full-diff.md)
- [16 浏览分页 Commit Graph 与提交详情](16-browse-paged-commit-graph.md)
