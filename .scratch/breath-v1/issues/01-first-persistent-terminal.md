# 打开第一个可持久化的原生终端

Status: ready-for-agent

## Parent

[Breath v1 PRD](../spec.md)

## What to build

交付从选择本地项目目录、创建工作区和工作会话，到在右侧原生终端中运行用户默认 login shell 的第一条完整路径。工作区与工作会话需要进入本地持久化，终端通过隔离的 TerminalEngine 接口接入 libghostty。

## Acceptance criteria

- [ ] 用户可以选择本地目录并在会话树中看到唯一工作区和首个工作会话
- [ ] 新工作会话只启动空 login shell，cwd 是工作区根目录，不自动启动 Agent
- [ ] 用户可以输入命令并看到输出
- [ ] 工作区和工作会话元数据通过公开工作台用例往返持久化
- [ ] macOS 14 arm64 Debug 构建与高层用例测试通过

## Blocked by

None - can start immediately
