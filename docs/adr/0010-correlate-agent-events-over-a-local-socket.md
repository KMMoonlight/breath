# 通过本地 Socket 关联 Agent 事件

Breath 为每个终端窗格注入工作区、工作会话和窗格标识，用户从该窗格启动的 Agent CLI 及其 hooks 会继承这些标识。集成脚本通过仅限本机的 Unix Domain Socket 把 Agent 事件发送给 Breath；缺少 Breath 标识或应用不可连接时静默退出，从而不解析易变的终端文本、不依赖云端服务，也不会把其他终端中的 Agent 错误关联到 Breath。
