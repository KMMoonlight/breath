# 编辑和回滚工作树并创建 Git Safety Snapshot

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

允许从 Diff 直接编辑真实工作树，并在文件、Hunk 或行级 Rollback 及其他高风险操作前尽力创建可检查、可恢复的 Git Safety Snapshot。

## Acceptance criteria

- [x] 编辑本地一侧会安全写入真实文件并刷新仓库快照
- [x] Rollback 支持文件、Hunk 和行，并在执行前重新验证补丁
- [x] 不可逆覆盖前显示 Root、路径和影响范围确认
- [x] Snapshot 可按操作和时间浏览、比较并恢复文件或片段
- [x] 默认保留最近 5 个修改工作日，设置为 0 可禁用
- [x] Snapshot 位于缓存，失败或被磁盘清理不阻塞 Git 操作
- [x] 产品明确说明 Snapshot 不是连续 Local History

## Blocked by

- [04 让 Git 操作跨页面运行并按 Root 排队](04-run-root-scoped-operations-in-background.md)
- [08 使用完整 Diff 审阅本地变更](08-review-local-changes-with-full-diff.md)
