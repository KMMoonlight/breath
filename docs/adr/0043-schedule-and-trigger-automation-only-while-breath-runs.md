# 只在 Breath 运行期间调度和触发自动化

自动化调度器属于 Breath 应用进程，不安装 launchd、登录项守护进程或云端执行器。关闭主窗口不停止调度，完全退出和用户主动睡眠期间不执行、不补跑；重新激活时只聚合记录错过的 occurrence。所有触发方式进入同一个并发队列和状态机。

本机脚本使用显式安装到 `~/.local/bin` 的 `breath trigger <短码>`，通过权限为 `0600` 的当前用户 Unix Domain Socket 请求已经运行的 Breath。命令不启动 GUI、不携带 payload、不等待 Agent 最终回答。这个边界保持触发地址简短且不暴露 HTTP 服务，代价是 Breath 未运行时外部触发会明确失败。
