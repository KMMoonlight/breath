# Keep the Git workbench independent from Agent context

Breath embeds a general-purpose Git GUI scoped to a workspace repository, but the Git workbench does not depend on Work Sessions, Terminal Panes, Agent state, or Agent lifecycle events. This preserves predictable Git behavior and lets users operate the repository directly; the trade-off is that Breath will not infer Git intent, select changes, or alter workflows from Agent activity.
