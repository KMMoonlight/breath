# 用 Codex 打通首个完整 Agent 增强路径

Status: implemented

## Parent

[Breath v1 PRD](../spec.md)

## What to build

以 Codex 建立首个端到端 Agent Adapter 与 Agent Integration：用户级 hook 的可逆安装、本地 Socket 事件、四态展示、官方标题、会话标识、一窗格一绑定，以及正常退出和归档后的原生对话恢复。

## Acceptance criteria

- [x] Codex 集成必须由用户显式启用，合并并备份用户级配置且可完整卸载
- [x] Hook 缺少 Breath 关联或无法连接时静默结束，不写项目配置
- [x] 官方事件映射到空闲、运行中、需要处理、回合完成四态
- [x] 首个官方标题命名父工作会话，窗格使用自身标题且均不可手动修改
- [x] 捕获官方会话标识并在干净退出或归档后按选择时机恢复
- [x] 同窗格新受支持 Agent 绑定替换旧绑定，不删除 Codex 自身对话
- [x] 契约测试证明事件不包含提示词、回复、工具内容或 transcript

## Blocked by

- [07 归档、恢复和永久删除工作会话](07-work-session-archive.md)
