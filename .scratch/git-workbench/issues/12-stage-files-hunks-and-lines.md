# 切换到原生 Staging 并编辑三方 Index

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

提供与 Changelist 互斥的原生 Git Staging Area，支持文件、Hunk、行级 Stage/Unstage 和 HEAD、Staged、Local 三方编辑。

## Acceptance criteria

- [x] 工作区可以在 Changelist 与 Staging 之间切换且界面互斥
- [x] 切换到 Staging 后 Changelist 元数据保留，切回后重新关联
- [x] Unstaged 与 Staged 真实反映 Git Index
- [x] 支持文件、Hunk 和行级 Stage/Unstage
- [x] 三方编辑原子更新真实 Index，失败后重新读取真实状态
- [x] 外部终端修改 Index 后界面自动刷新
- [x] 切换与 Index 编辑通过真实仓库测试

## Blocked by

- [10 通过文件级 Changelist 完成首次 Commit](10-commit-a-file-changelist.md)
- [11 按 Hunk 和行组织 Changelist 并隔离 Index](11-commit-changelist-hunks-and-lines.md)
