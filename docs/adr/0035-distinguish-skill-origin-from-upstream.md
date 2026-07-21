# 区分 Skill 安装来源与 Skill 上游

Breath 的 Skill 安装记录使用判别联合保存来源：ZIP 安装只记录 `.zip` 来源分类；GitHub 和 skills.sh 安装记录 `.remote(upstream)`，其中才包含 Repo、来源相对路径、引用和 Commit。两类记录都位于 Breath SQLite，不向 Skill 目录写入 sidecar，也不决定 Skill 是否已安装。

ZIP 来源记录仅用于在列表中恢复用户选择的安装来源，不构成 Skill 上游，不提供更新，也不会因为安装后内容变化而标记为“本地已修改”。只有带可验证远程上游的记录才能检查更新并产生“本地已修改”状态。本决策扩展 ADR 0034 中的非侵入式记录边界，同时保持 Agent 目录为安装状态和 Skill 内容的唯一事实来源。
