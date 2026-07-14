# 使用 Sparkle 与 GitHub 托管应用更新

Breath 使用 Sparkle 2 实现应用内版本检查、更新提示、Developer ID 与 EdDSA 签名验证、安装和重启。GitHub 是唯一发布基础设施：GitHub Actions 构建并公证 Universal Binary，公开 GitHub Releases 托管安装包与更新包，GitHub Pages 托管签名后的 appcast；Breath 不建设更新服务器，也不在客户端保存 GitHub 凭据。更新可以自动检查，但不能静默强制安装，必须由用户确认。安装重启复用正常退出的安全流程：存在终端进程时再次确认，确认后保存布局、Agent 会话标识和恢复状态并终止全部终端进程；更新重启后只立即处理更新前选中的工作会话，其他会话在用户选中时再恢复，普通 Shell 只恢复为空终端布局。取消安装不会中断进程。
