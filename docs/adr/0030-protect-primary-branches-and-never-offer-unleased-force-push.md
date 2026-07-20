# Protect primary branches and never offer unleased force push

The Git workbench protects `main` and `master` by default and lets users configure additional protected-branch patterns. Protected branches cannot be force-pushed or subjected to operations that rewrite already-pushed history, such as dropping or editing published commits. Where force push is allowed, Breath only offers `git push --force-with-lease`, never plain `--force`, and confirms the target Git Root, branch, and affected commits before execution. Without hosting-platform integration, protection rules remain local to Breath.
