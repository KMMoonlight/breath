# 通过用户安装的 Git LFS 管理对象与 Locks

Status: implemented

## Parent

[Breath Git 工作台 PRD](../spec.md)

## What to build

探测并使用用户安装的 Git LFS，识别 Pointer、预览已下载对象、Fetch/Pull LFS 对象并查看 Locks。

## Acceptance criteria

- [x] 探测 Git LFS 版本并在缺失时说明能力不可用
- [x] 按 `.gitattributes` 和 Pointer 信息识别 LFS 文件
- [x] 对象已下载时预览真实内容，未下载时显示 Pointer 元数据
- [x] 支持 Fetch/Pull LFS 对象和查看 LFS Locks
- [x] 使用用户 Git 配置、Hooks、Filters 和认证
- [x] Breath 不安装 Git LFS，也不管理托管平台账号
- [x] 基础能力与可选 Git LFS CI Lane 测试

## Blocked by

- [08 使用完整 Diff 审阅本地变更](08-review-local-changes-with-full-diff.md)
- [18 通过现有凭证安全 Fetch Remote](18-fetch-with-existing-credentials.md)
