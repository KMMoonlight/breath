# Exclude managed worktrees from system backup

Breath marks its application-support `worktrees/` directory as excluded from Time Machine and iCloud-style backup. Managed worktrees can contain large dependencies, caches, and linked Git metadata that may be invalid when restored independently of the source repository; users protect durable work by committing to the task branch and then merging or pushing it through normal Git workflows, while Breath preserves active and archived worktrees only on the local machine until explicit deletion.
