# 通过现有凭证安全 Fetch Remote

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

通过用户 Git CLI、Credential Helper、SSH Agent 和原生 Askpass 对话完成 Fetch，不由 Breath 保存认证秘密。

## Acceptance criteria

- [x] Fetch 展示各 Remote 的进度、更新引用和原始错误
- [x] 支持用户名、密码、Token、SSH Passphrase 和 Host Key 确认请求
- [x] 现有 Credential Helper、SSH Agent 和 Keychain 保持生效
- [x] 秘密仅传给当前进程，持久化由 Helper 决定
- [x] Console、数据库和日志不包含认证秘密
- [x] 受控 Helper/Askpass 与本地 Remote 测试覆盖认证边界

## Blocked by

- [04 让 Git 操作跨页面运行并按 Root 排队](04-run-root-scoped-operations-in-background.md)
- [06 安全发现并聚合多个 Git Root](06-discover-and-aggregate-multiple-git-roots.md)
- [15 浏览和管理 Branch、Tag、Remote 与 Upstream](15-manage-branches-tags-remotes-and-upstreams.md)
