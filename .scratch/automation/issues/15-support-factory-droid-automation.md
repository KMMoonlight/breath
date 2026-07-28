# 支持 Factory Droid 自动化运行

Status: ready-for-agent

## Parent

[Breath 自动化](../spec.md)

## What to build

把既有 Automation Run 路径扩展到 Factory Droid。已安装且版本兼容的 Factory Droid 可以在创建和编辑表单中选择，并通过专属无头适配器在同一只读 Workspace 沙盒、运行生命周期和结果契约下执行固定 Prompt。

本切片覆盖 Factory Droid 对应的 PRD User Stories 19–22、93、99–106、127–137。

## Acceptance criteria

- [ ] Factory Droid 描述符在同一 Agent 支持矩阵中声明安装检测、最低兼容版本和 Automation Runner 能力，不维护第二份 Agent 名单
- [ ] 未安装 Factory Droid 不出现在自动化选择器；版本过旧时显示禁用、当前版本和升级说明
- [ ] 适配器以无交互方式执行固定 Prompt，沿用 Factory Droid 默认模型、认证、配置和全局 Skills，不创建或恢复 Agent Conversation
- [ ] 运行直接读取真实 Workspace，并继承既有进程沙盒、临时 HOME、出站网络、只读项目和无 GUI/无交互批准边界
- [ ] 适配器可靠提取单个最终回答；正常非空回答、非零退出、空回答、启动失败和认证失败映射到统一运行状态与脱敏摘要
- [ ] 取消、超时、删除和应用退出能终止 Factory Droid 完整进程树并清理临时目录
- [ ] Agent 被卸载或版本变得不兼容时相关自动化进入依赖暂停，恢复后仍要求用户显式启用
- [ ] 运行记录展示 Factory Droid，并仅在可靠可知时记录实际模型；输出仍遵守 256 KiB 和最近五次规则
- [ ] 适配器契约测试覆盖版本矩阵、最终回答提取、错误分类、取消、超时、沙盒继承和 Workspace 内容不变
- [ ] App Shell 验证覆盖 Factory Droid 选择、禁用原因、依赖暂停和结果展示

## Blocked by

- [管理自动化清单与依赖状态](02-manage-automation-library-and-dependencies.md)
- [安全地取消、超时和中断自动化运行](03-control-timeout-sleep-and-interruption.md)
