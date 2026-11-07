---
name: context-sync
description: Audit and update Cerebro's .agents knowledge files against the actual codebase so agent context never rots. Use at every release point, after a plan merges with deviations, or when the owner says the docs feel stale.
---

# Context sync: keep `.agents/` truthful

`.agents/context/*.md` and `.agents/rules/*.md` must describe the code as it exists, not as it was planned.

1. Work on a branch from `develop`, `chore/context-sync-<date>`. It lands through a PR into `develop`.
2. Diff each file's claims against reality:
   - modules and dependencies against `Package.swift`, `Cerebro.podspec` and `Cerebro.xcodeproj`
   - the SwiftProtobuf range against `Package.swift` and the podspec, and its pin against `Package.resolved`
   - folders against `project-structure.md`
   - commands against what actually runs
   - public API against `README.md`
3. Update the files to match. The code wins, unless the difference breaks a logged decision. Report that as a regression instead of documenting it.
4. Real decision drift gets a new dated row in `.agents/memory/decisions.md`. Never edit or delete existing rows.
5. Don't touch plan files. They are historical specs.
6. Move every `progress.md` activity entry dated before the latest release tag into `history.md`, newest first, text unchanged.
7. Put a divergence table in the PR body: file, claim, reality, action taken.
