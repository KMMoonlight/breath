# Issue tracker: Local Markdown

Issues and specs (also called PRDs) for this repo currently live as Markdown files in `.scratch/` because the repository has no configured Git remote.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`
- The PRD is `.scratch/<feature-slug>/spec.md`
- Implementation issues are one file per ticket under `.scratch/<feature-slug>/issues/`, numbered from `01`
- Triage state is recorded as a `Status:` line near the top of each issue file
- Comments and conversation history are appended under a `## Comments` heading

## Publishing

When a skill says “publish to the issue tracker,” create or update the corresponding file under `.scratch/`. After this repository is connected to GitHub and authenticated, this configuration may be changed to GitHub Issues and existing specs can be published there without changing their content.
