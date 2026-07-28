# Breath 发布手册

Breath 通过 GitHub Releases 发布经过 Developer ID 签名和 Apple 公证的 Universal `.app` 压缩包，并通过 GitHub Pages 提供 Sparkle appcast。应用不启用 App Sandbox，也不依赖 Breath 后端或用户 GitHub Token。

## 一次性配置

1. 在仓库 Pages 设置中选择 **GitHub Actions** 作为发布来源。
2. 创建 Sparkle Ed25519 密钥；私钥只进入 GitHub Actions Secret，公钥进入构建产物的 `Info.plist`。
3. 在 GitHub Actions 中添加：
   - `DEVELOPER_ID_APPLICATION_P12`
   - `DEVELOPER_ID_APPLICATION_PASSWORD`
   - `APPLE_ID`
   - `APPLE_APP_SPECIFIC_PASSWORD`
   - `APPLE_TEAM_ID`
   - `SPARKLE_PRIVATE_KEY`
   - `SPARKLE_PUBLIC_KEY`
4. 确保仓库 Actions 可写 Releases，`github-pages` environment 允许 tag 工作流部署。

## 发布

推送语义版本 tag，例如 `v1.0.0`。工作流将：

1. 构建固定 revision 的 Universal libghostty。
2. 运行全部测试，并分别构建 arm64 与 x86_64 Breath。
3. 合并 Universal executable，嵌入 Sparkle，完成 Developer ID 签名、公证和 stapling。
4. 用 Sparkle Ed25519 私钥签名更新包并生成 appcast。
5. 上传 zip 到 GitHub Release，将 appcast 部署到 GitHub Pages。

Sparkle 自动检查更新，但 `SUAutomaticallyUpdate` 为 `false`，安装仍由用户确认。安装触发应用退出时，复用 Breath 的正常退出协调：先保存布局和 Agent session ID，再停止所有终端。

## 本地打包

开发验证直接运行 `scripts/build-app.sh`。脚本会在缺少
`GhosttyKit.xcframework` 时自动构建它，随后生成 ad-hoc 签名的
Universal `.app` 和 `.zip`；本地包不会启动 Sparkle 更新检查。

需要模拟正式发布参数时，先运行 `scripts/build-libghostty.sh`，再设置
`VERSION`、`SPARKLE_FEED_URL` 和 `SPARKLE_PUBLIC_KEY` 执行
`scripts/package-app.sh`。未设置 `CODE_SIGN_IDENTITY` 时只生成供本机验证的
ad-hoc 签名包；正式发行必须使用 Developer ID 并设置 `NOTARIZE=1`。
