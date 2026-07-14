# 提供终端配置样式

Status: implemented

## Parent

[Breath v1 PRD](../spec.md)

## What to build

提供字体、字号、颜色主题和光标等终端内部样式，实时应用于终端窗格并持久化，同时保持 Breath 配置与 Ghostty 配置完全独立。

## Acceptance criteria

- [x] 字体、字号、颜色主题和光标样式可配置并持久化
- [x] 变化只影响终端内部并应用到现有与新窗格
- [x] 不提供 Shell、快捷键、分屏或 Agent 行为选项
- [x] 不读取、导入或同步 Ghostty 配置
- [x] TerminalEngine 样式契约测试通过

## Blocked by

- [02 完善原生终端日常交互](02-native-terminal-interaction.md)
