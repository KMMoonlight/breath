# 按固定间隔运行自动化

Status: ready-for-agent

## Parent

[Breath 自动化](../spec.md)

## What to build

在既有本地调度器上增加固定 Interval 触发。用户选择正整数和分钟、小时或天后，自动化从启用或规则编辑时刻建立锚点，按固定持续时间触发，而不是在上一次运行完成后重新计时。

本切片覆盖 PRD User Stories 60–64、67、70–74。

## Acceptance criteria

- [ ] 创建和编辑表单支持正整数与分钟、小时、天三种单位，并展示可理解的触发摘要和下一次时间
- [ ] Interval 最短为 1 分钟、最长为 30 天，零值、负值、溢出和越界组合不能保存
- [ ] 新建并启用 Interval 自动化后等待完整间隔，不因创建立即运行
- [ ] 修改 Interval 数值、单位或切换到 Interval 时以保存时刻建立新锚点，并等待完整新间隔
- [ ] 禁用期间不触发、不记录错过；重新启用时建立新锚点，而不是补算禁用期间的周期
- [ ] Interval 以持续时间计算，不受系统时区变化影响，也不以上一次运行结束时间重新计时
- [ ] 应用进程退出或系统睡眠期间的一个或多个 Interval occurrence 不补跑，只形成一条带次数与时间范围的已错过记录
- [ ] 窗口关闭但 Breath 仍运行时 Interval 继续调度；完全退出时没有独立执行器继续运行
- [ ] Interval occurrence 进入统一并发队列，并遵守同一自动化 in-flight 时跳过和全局并发上限
- [ ] 运行成功、失败、超时或取消不会改变既有 Interval 锚点和下一 occurrence
- [ ] 公开用例测试使用虚拟时钟覆盖单位换算、边界、锚点、编辑、重新启用、时区变化、睡眠、离线聚合和队列接入
- [ ] App Shell 验证覆盖 Interval 表单、校验、摘要、下一次时间、已错过记录和可访问性语义

## Blocked by

- [按单次、每日和每周计划运行自动化](06-run-on-once-daily-and-weekly-schedules.md)
