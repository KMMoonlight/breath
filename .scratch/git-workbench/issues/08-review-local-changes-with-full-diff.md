# 使用完整 Diff 审阅本地变更

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

把现有只读 Diff 原型扩展为 JetBrains 风格的完整文本审阅器，支持统一与并排视图、导航、过滤和大文件降级。

## Acceptance criteria

- [x] 支持 Side-by-side 和 Unified Diff
- [x] 支持上一/下一差异与文件、搜索、复制和 Soft Wrap
- [x] 支持空白忽略、空白字符显示和折叠未变更区域
- [x] 本地 Diff 保留文件、Hunk 和行级稳定选择
- [x] 二进制与超大文件显示元数据和可用系统预览，不自动文本 Diff
- [x] Diff 偏好在应用设置中持久化
- [x] Diff 模型和真实仓库读取通过行为测试

## Blocked by

- [02 恢复三列 Git 页面布局与浏览状态](02-restore-three-column-workbench-state.md)
- [03 让仓库快照持续反映真实 Git 状态](03-refresh-authoritative-repository-snapshots.md)
