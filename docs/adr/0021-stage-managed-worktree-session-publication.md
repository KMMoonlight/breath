# Stage managed-worktree creation before publication

Managed Worktree creation and cleanup do not form an atomic transaction: Git references and worktree metadata, filesystem directories, terminal processes, and Breath persistence can each succeed or fail independently. Breath therefore uses staged publication and compensating actions.

A Worktree Session remains unpublished while Breath creates and validates the checkout, launches its first terminal, and saves the completed snapshot. On failure, Breath stops the terminal and attempts to remove the unpublished worktree and any branch created by that operation. Compensation can also fail; in that case Breath reports the original and cleanup errors together and preserves any state whose safe removal cannot be proven.

The current implementation does not persist a pending-cleanup record or guarantee automatic cleanup on a later launch. Startup validates persisted Worktrees, but orphan discovery and retryable cleanup records remain follow-up work.
