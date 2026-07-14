# 通过 GitHub 和 Sparkle 发布及更新 Breath

Status: implemented-awaiting-release-verification

## Parent

[Breath v1 PRD](../spec.md)

## What to build

建立站外发行和应用内更新的完整路径：Universal Binary、Developer ID 签名、公证、GitHub Releases、GitHub Pages appcast、Sparkle 双重签名验证及复用正常退出协调的安装重启。

## Acceptance criteria

- [x] 构建产物支持 arm64 与 x86_64，最低系统为 macOS 14
- [ ] 发布产物通过 Developer ID 签名与 Apple 公证且不启用 App Sandbox
- [ ] GitHub Releases 托管安装与更新包，GitHub Pages 托管签名 appcast
- [x] Sparkle 自动检查但只在用户确认后安装，取消不影响进程
- [x] 安装重启复用正常退出流程并遵守最后选择的按需恢复策略
- [x] 更新同时验证 Apple Code Signing 与 EdDSA，不需要 GitHub Token 或 Breath 后端

## Release verification

本地 Universal ad-hoc 包已验证。Developer ID、公证、GitHub Release 与 Pages 的实际发布需要仓库远端和发布 secrets，将在首次版本 tag 的工作流中完成验证。

## Blocked by

- [05 正常退出并按需恢复工作会话](05-clean-exit-and-lazy-restore.md)
