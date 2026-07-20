# Create managed-worktree sessions atomically

Breath exposes a Worktree Session only after its managed Git worktree, persisted session state, and first terminal have all been created successfully. A failure rolls back every completed step; if filesystem or Git cleanup cannot finish, Breath persists a pending-cleanup record, reports its path, and retries cleanup on a later launch instead of exposing a partially created session. This adds recovery state, but prevents half-created worktrees from masquerading as usable work sessions.
