# 提供 JetBrains 风格快捷键、焦点作用域与设置管理

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

为全部 Git 命令注册 JetBrains macOS 风格默认快捷键，按焦点作用域路由，并在设置中展示、修改和诊断冲突。

## Acceptance criteria

- [x] Git 局部快捷键仅在 Git 工作台焦点内生效
- [x] Terminal 现有快捷键不被 Git 页面抢占
- [x] 只有无歧义的 Open Git、Commit、Push 等命令可配置为全局
- [x] 所有 Git 命令在 Shortcuts 设置页可见并可修改
- [x] 设置页显示作用域和冲突命令
- [x] 菜单项与工具提示展示当前生效快捷键
- [x] 默认映射、焦点路由和冲突通过测试

## Blocked by

- [07 从 Git 空状态初始化或克隆仓库](07-initialize-or-clone-from-empty-state.md)
- [12 切换到原生 Staging 并编辑三方 Index](12-stage-files-hunks-and-lines.md)
- [14 支持 Commit 模板、历史消息、Amend 与签名](14-support-commit-templates-amend-and-signing.md)
- [17 按需查看 File History 与 Blame](17-show-file-history-and-blame.md)
- [23 Cherry-pick、Revert 并解决冲突](23-cherry-pick-revert-and-resolve-conflicts.md)
- [24 使用 Interactive Rebase 重写本地历史](24-interactively-rebase-local-history.md)
- [25 安全执行 Undo Last Commit 与 Reset](25-undo-last-commit-and-reset-safely.md)
- [26 只 Push 到选中的 Commit](26-push-up-to-selected-commit.md)
- [27 跨多个 Git Root 分别 Commit 并呈现部分结果](27-commit-across-multiple-roots.md)
- [28 显式同步多个 Root 的分支操作](28-synchronize-explicit-multi-root-branch-operations.md)
- [29 管理标准 Git Stash](29-manage-standard-git-stashes.md)
- [30 Shelve 局部修改并导入、导出 Patch](30-shelve-patches-and-import-export.md)
- [31 将 Submodule 作为显式 Git Root 管理](31-manage-submodules-as-explicit-roots.md)
- [32 通过用户安装的 Git LFS 管理对象与 Locks](32-use-installed-git-lfs.md)
