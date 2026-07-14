# 最小化 Agent Hook 数据

Agent 集成只向 Breath 发送 Agent 类型与版本、生命周期事件与时间、Agent 原生会话标识、Agent CLI 通过官方接口提供的原生标题、工作目录及 Breath 窗格关联标识。提示词、Agent 回复、工具输入输出、完整 transcript 及其路径都不进入事件通道或持久化存储；Breath 不调用额外模型生成标题。
