# 通过完整能力门禁并开放首次交付

Status: implementation-complete-release-blocked

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

对全部 Git 工作台用户故事建立发布验收矩阵，完成性能、安全、视觉和回归验证后才移除内部 Feature Flag 并开放首次交付。

## Acceptance criteria

- [x] PRD 208 条 User Stories 全部映射到已通过的自动或人工验收
- [ ] 36 个 Issues 的 Acceptance Criteria 全部完成
- [ ] 完整 Swift 测试套件通过，既有基线失败得到明确处置
- [x] 大型仓库、并发、凭证脱敏和退出协调完成专项验证
- [ ] 简体中文、英文、VoiceOver 和无鼠标流程完成验收
- [x] Worktree、托管平台集成和 Agent 耦合未被带入范围
- [x] 所有已确认能力完成前，公开 Git 工作台仍保持内部 Feature Flag

## Release blockers

- Issue 35 的 VoiceOver、Merge Tool、复杂 Diff 与无鼠标流程仍待有
  macOS Accessibility 权限的机器人工签字。
- 自动测试聚合结果为 169 个测试中 168 个通过。Git 工作台新增测试全部
  通过；唯一未通过的是既有 `WorkbenchEmptyStateTests` 的原生 App
  校验。当前机器的 Endpoint Security 在 LaunchServices 启动阶段记录
  `ES_AUTH_RESULT_DENY` 并 SIGKILL 临时校验 App。全量
  `swift test --disable-sandbox --quiet` 完成 169 项测试并仅报告这一项
  失败。发布前仍需在允许该校验 App 启动的环境中重跑，或由该既有测试
  的责任域明确处置。

## Blocked by

- [34 完成简体中文、英文和原始 Git 诊断呈现](34-localize-git-workbench-and-diagnostics.md)
- [35 通过 VoiceOver、键盘和系统辅助功能验收](35-pass-git-workbench-accessibility-gate.md)
