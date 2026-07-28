# 通过 breath trigger 短码触发自动化

Status: ready-for-agent

## Parent

[Breath 自动化](../spec.md)

## What to build

交付外部命令触发的完整路径。用户把自动化切换为外部触发后获得稳定短码和可复制的 `breath trigger <短码>`；本机脚本通过当前用户专属 Unix Domain Socket 请求已经运行的 Breath 启动或排队固定 Prompt，不启动 GUI，也不提供 HTTP webhook 或动态输入。

本切片覆盖 PRD User Stories 42、75–92。

## Acceptance criteria

- [ ] 创建和编辑表单支持“外部命令触发”，保存后为该自动化生成高熵、便于复制且与内部 ID 分离的稳定短码
- [ ] 编辑名称、Prompt、Workspace、Agent 或最大时长不改变短码；重新生成需要确认并原子废止旧短码
- [ ] 切换离开外部触发会使短码立即失效，再次切回时生成新短码；删除自动化同样使短码失效
- [ ] 详情和更多菜单展示并复制 `breath trigger <短码>`，不展示 localhost、端口或自定义 URL
- [ ] CLI 只接受一个短码，不接受额外 payload、Prompt 参数、stdin 或运行时变量
- [ ] CLI 通过版本化、同一 macOS 用户可访问且权限为 `0600` 的 Unix Domain Socket 与已运行 Breath 通信，不监听 HTTP
- [ ] Breath 未运行时 CLI 不启动应用，返回非零退出码和 “Breath is not running”
- [ ] 有效请求被立即启动或排队时 CLI 返回零且不等待最终回答；短码无效、已废止、自动化禁用、依赖暂停或已有 in-flight 时返回非零和清理后的原因
- [ ] 有效外部请求进入统一并发队列，使用已保存固定 Prompt；自身已有 in-flight 时仍产生既有“已跳过”历史
- [ ] Breath 提供用户明确点击的一键安装，把 CLI 入口安装到 `~/.local/bin/breath`，不请求管理员权限、不修改 PATH、不覆盖非 Breath 管理的同名文件
- [ ] 自动化触发消息与现有 Agent 事件使用独立版本化消息类型，不能伪造或创建 Work Session、Terminal Pane 或 Agent Conversation
- [ ] 公开用例测试覆盖短码生命周期、启用和依赖规则、队列接入及无动态输入；UDS 契约测试覆盖权限、协议版本、应用缺席和并发请求
- [ ] App Shell 验证覆盖外部触发表单、复制、重新生成确认、CLI 缺失安装提示、错误状态、键盘和 VoiceOver 语义

## Blocked by

- [管理自动化清单与依赖状态](02-manage-automation-library-and-dependencies.md)
- [展示最近五次结果与未读角标](04-show-five-results-and-unread-badge.md)
- [按全局并发上限排队运行自动化](05-queue-runs-by-global-concurrency.md)
