# 保存经过脱敏的 Git Console 历史

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

在底部 Console 展示 Breath 发起的 Git 命令、进度和结果，并按工作区持久化有限、经过脱敏的历史。

## Acceptance criteria

- [x] Console 展示命令、开始结束时间、退出状态和流式输出
- [x] 密码、Token、Passphrase、URL 凭证和秘密环境变量不会进入展示或持久化
- [x] 每个工作区最多保留最近 7 天或 500 条记录，以先达到者为限
- [x] 用户可以清空历史或关闭持久化，关闭后只保留当前应用会话
- [x] Console 可折叠，并能从操作徽标重新打开对应记录
- [x] 跨重启、裁剪和秘密扫描通过持久化测试

## Blocked by

- [04 让 Git 操作跨页面运行并按 Root 排队](04-run-root-scoped-operations-in-background.md)
