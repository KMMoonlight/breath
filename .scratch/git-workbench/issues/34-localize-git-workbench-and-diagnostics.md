# 完成简体中文、英文和原始 Git 诊断呈现

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

为完整 Git 工作台提供简体中文和英文界面，并在本地化解释旁始终保留 Git 原始数据和错误。

## Acceptance criteria

- [x] 所有 Breath Git 文案具有简体中文和英文资源
- [x] Commit Message、分支、Tag、路径和原始输出保持用户原文
- [x] 已知错误提供本地化解释，同时保留完整原始 Git 错误
- [x] Rebase、Cherry-pick 等术语遵循项目词汇表和行业惯例
- [x] 未翻译键、格式占位符和两种语言布局通过自动测试
- [x] Console 与诊断不会因本地化截断排障信息

## Blocked by

- [33 提供 JetBrains 风格快捷键、焦点作用域与设置管理](33-configure-jetbrains-style-git-shortcuts.md)
