# 从 skills.sh 搜索、审计并安装 Skill

Status: implemented

## Parent

[Breath 全局 Skills 管理](../spec.md)

## What to build

在统一在线输入区把普通关键词交给可替换的 skills.sh Provider，展示候选、安装量和可用安全审计，再将用户选择解析到实际公开上游并复用现有安装流程。审计是辅助信号而不是安全认证，高风险结果经过额外确认后仍由用户决定。

本切片覆盖 PRD User Stories 55–64、94、123、126。

## Acceptance criteria

- [x] 统一在线输入区能区分 GitHub 地址、Repo 简写与普通搜索词；用户切换来源或返回上一步时保留仍有效的选择
- [x] skills.sh 集成封装为可注入、可替换 Provider，页面和安装用例不依赖具体网页或接口结构
- [x] 搜索结果至少展示名称、说明、来源和安装量，并支持选择一个结果进入已有候选解析流程
- [x] 有审计结果时展示风险等级和检查时间；没有结果时明确显示“未知”，绝不显示为安全
- [x] 高风险和严重风险候选在最终安装前需要额外确认，但完成文件和 `SKILL.md` 审阅后不被永久硬拦截
- [x] 选择结果后解析并保存实际上游 Repo、相对位置、引用和 Commit，而不是把 skills.sh 列表项当作 Skill 内容来源
- [x] skills.sh 候选复用多 Skill 选择、目标选择、强制预览、同名处理、原子写入和逐目标结果
- [x] skills.sh 不可用、超时或接口变化时只影响在线搜索；本地列表、ZIP、指定 GitHub、已有来源对账和卸载继续工作
- [x] 网络请求只发送完成查询和来源解析所需的信息，不上传 Skill 内容、安装目录、Agent 列表或历史搜索记录，也不引入 Breath 账户、后端或遥测
- [x] Provider 测试覆盖关键词映射、安装量、安全/未知/高风险状态、结果选择、实际来源解析、不可用、超时和错误隔离
- [x] App Shell 测试覆盖统一输入识别、返回保留状态、高风险确认、取消零写入及中英文无障碍语义

## Blocked by

- [从公共 GitHub 仓库安装并记录来源](06-install-from-public-github-and-record-provenance.md)
