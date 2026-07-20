# 支持 Commit 模板、历史消息、Amend 与签名

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

完善 Commit 工作流，使用 Git 配置中的模板和签名工具，并支持最近消息、Amend 与 Commit and Push 的提交阶段。

## Acceptance criteria

- [x] 新草稿可读取仓库 Commit Template
- [x] 用户可选择最近提交消息
- [x] Amend 明确展示将被修改的 Commit 和最终内容
- [x] GPG 或 SSH 签名由用户 Git 配置和现有工具处理
- [x] 签名交互和错误进入 Operation 与 Console
- [x] Commit and Push 可把成功提交交给后续 Push 流
- [x] 模板、Amend 和可控签名程序通过真实仓库测试

## Blocked by

- [10 通过文件级 Changelist 完成首次 Commit](10-commit-a-file-changelist.md)
- [13 运行 Commit Hooks 与工作区提交前检查](13-run-commit-hooks-and-workspace-checks.md)
