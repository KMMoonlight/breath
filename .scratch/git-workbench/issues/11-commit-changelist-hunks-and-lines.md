# 按 Hunk 和行组织 Changelist 并隔离 Index

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

把 Changelist 扩展到 Hunk 和行级分组，并确保部分提交不会破坏用户现有 Git Index 或未选择修改。

## Acceptance criteria

- [x] Hunk 和选中行可移动到任意 Changelist
- [x] 外部文件修改后可安全重映射的片段保留归属
- [x] 无法唯一映射的片段进入待确认状态且不能静默提交
- [x] 部分提交只包含选择的 Hunk 或行
- [x] 提交前后的用户 Index 内容保持不变
- [x] 失败时不会通过破坏再重建 Index 掩盖问题
- [x] 真实仓库测试覆盖外部修改、部分提交和 Index 隔离

## Blocked by

- [10 通过文件级 Changelist 完成首次 Commit](10-commit-a-file-changelist.md)
