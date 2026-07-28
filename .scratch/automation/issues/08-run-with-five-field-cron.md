# 使用五字段 Cron 运行自动化

Status: ready-for-agent

## Parent

[Breath 自动化](../spec.md)

## What to build

在既有本地调度器上增加自定义 Cron 触发。用户可以输入标准五字段表达式并在保存前看到当前 macOS 时区下未来三次 occurrence；每月等复杂规则通过 Cron 表达，不增加单独的每月表单。

本切片覆盖 PRD User Stories 54–59、65、68、70–74。

## Acceptance criteria

- [ ] 创建和编辑表单提供五字段 Cron 输入，并明确字段顺序为分钟、小时、日、月、星期
- [ ] 解析器拒绝秒字段、字段数量错误、越界值、非法步长和 `@daily` 等宏，错误时禁止保存
- [ ] 合法表达式实时展示当前 macOS 时区、规则摘要和未来三次预计 occurrence
- [ ] 每月、指定月份或月内日期通过 Cron 表达；页面不出现单独“每月”触发类型
- [ ] 创建、编辑和重新启用 Cron 自动化后等待下一个未来 occurrence，不立即运行或补跑
- [ ] Cron 使用当前系统 TimeZone 动态计算；时区变化后重新计算未来 occurrence 而不改写表达式
- [ ] 因夏令时不存在的本地分钟视为错过，重复本地分钟最多触发一次，系统时钟回拨不会重复 occurrence
- [ ] 应用退出或睡眠期间错过的一个或多个 Cron occurrence 聚合成一条已错过记录，不补跑
- [ ] Cron occurrence 进入统一并发队列，并遵守启用状态、依赖暂停、in-flight 跳过和全局并发上限
- [ ] Cron 解析和预览是确定性的公开领域行为，不依赖 SwiftUI、数据库 row 或定时器实现细节
- [ ] 公开用例测试使用虚拟时钟覆盖常见表达式、月规则、范围/列表/步长、非法输入、时区、DST、离线聚合和队列接入
- [ ] App Shell 验证覆盖实时错误、保存禁用、未来三次预览、时区、触发摘要和可访问性语义

## Blocked by

- [按单次、每日和每周计划运行自动化](06-run-on-once-daily-and-weekly-schedules.md)
