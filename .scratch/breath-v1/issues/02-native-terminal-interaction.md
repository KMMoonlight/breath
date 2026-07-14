# 完善原生终端日常交互

Status: implemented

## Parent

[Breath v1 PRD](../spec.md)

## What to build

让真实终端具备可日常使用的 macOS 原生输入输出体验，包括中文输入法、选择、复制粘贴、焦点、滚动和尺寸变化，同时保持 TerminalEngine 边界不泄漏 libghostty 实现。

## Acceptance criteria

- [x] 中文输入法组合与提交文本可以正确送入 PTY
- [x] 键盘、选择、复制和粘贴符合 macOS 习惯
- [x] 视图尺寸变化会调整终端网格与 PTY
- [x] 焦点切换和滚动不破坏输入或渲染
- [x] TerminalEngine 集成测试覆盖关键输入输出契约

## Blocked by

- [01 打开第一个可持久化的原生终端](01-first-persistent-terminal.md)
