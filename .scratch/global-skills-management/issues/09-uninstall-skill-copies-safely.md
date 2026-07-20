# 按 Agent 安全卸载 Skill

Status: implemented

## Parent

[Breath 全局 Skills 管理](../spec.md)

## What to build

允许用户从聚合 Skill 详情中选择一个、多个或全部 Agent 副本卸载。普通目录使用 macOS 可恢复的废纸篓语义，外部符号链接只移除所选链接；各目标独立完成并立即按实际文件系统对账。

本切片覆盖 PRD User Stories 116–122、127、129。

## Acceptance criteria

- [x] 聚合 Skill 详情可以选择单个、多个或全部 Agent 副本，确认页展示每个真实路径、目录或链接类型及将执行的动作
- [x] 普通 Skill 目录移入 macOS 废纸篓而不是永久删除，并通过可注入的废纸篓边界返回可操作失败原因
- [x] 符号链接卸载只移除所选链接，不删除或修改共享目标、其他 Agent 链接或外部安装器状态
- [x] 原始 ZIP、GitHub Repo、skills.sh 条目及未选择的 Agent 副本不受卸载影响
- [x] 每个“Skill × Agent”独立报告成功或失败；一个目标失败不会恢复已经成功移除的其他目标
- [x] 卸载使用与安装、更新相同的每 Agent 目录串行协调，不同 Agent 可以并行处理
- [x] 成功卸载后移除对应来源记录并重新扫描真实目录；最后一个副本移除后聚合行消失，剩余副本则立即更新
- [x] 来源记录清理失败不会伪造磁盘上的已安装状态，重新对账后仍以实际文件为准并提供可重试诊断
- [x] 无法识别的项目不获得卸载动作，仍只能在 Finder 中定位
- [x] 结果页面分别列出成功和失败目标，错误提供简短可操作原因及不含凭据和敏感路径的可复制详情
- [x] 测试覆盖单个/多个/全部副本、普通目录进入模拟废纸篓、链接只解除、共享目标保持、部分失败、并发协调、来源记录清理和列表刷新

## Blocked by

- [同步外部变更并诊断异常 Skill](03-reconcile-external-changes-and-diagnose-invalid-skills.md)
- [从公共 GitHub 仓库安装并记录来源](06-install-from-public-github-and-record-provenance.md)
