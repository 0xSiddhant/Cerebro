---
name: new-plan
description: Draft a new numbered plan file for Cerebro (PLAN-XX) in the format the existing plans use, grounded in the spec and the real code, and closed with a self-review pass. Use whenever the owner asks to plan or draft new work, before writing any plan content.
---

# New plan: draft a Cerebro PLAN-XX file

## 1. Read before drafting

Read `.agents/context/architecture.md`, `.agents/rules/coding.md`, `.agents/rules/git.md`, the top of `.agents/memory/progress.md`, and `.agents/memory/decisions.md` for the area involved. Then read two recent plan files as live templates.

The plan number is one more than the highest row in `.agents/plans/README.md`. Plan 99 stays reserved for the backlog.

## 2. The section order

1. `# PLAN-XX — Title`
2. `## Goal`: one paragraph on what ships and why.
3. `## Gate`: what must be true first, the branch name, and any owner checkpoint.
4. `## Scope`: **In:** and **Out:**.
5. `## Decisions & reasoning`: one `###` per named decision, with the reasoning and what was rejected.
6. `## Public API`: a table of what the host app touches. Write "None" rather than omitting it.
7. `## Task checklist`: grouped by layer, with file paths. Every box starts unchecked.
8. `## Acceptance criteria`: numbered from 1, renumbered after any insertion.
9. `## Test checklist`: unit, integration and manual as the plan needs.
10. `## Open questions`: anything the spec leaves undecided, each with a recommendation. Omit the section if there are none.

## 3. Verify before designing

Read the real files a plan touches. Don't assume a signature from a name.

When a design leans on how iOS or a library behaves, and being wrong would matter, test it instead of trusting documentation. This project's first plans found three such gaps: `URLSession.shared` skips swizzled configuration getters, a public type named after its module breaks the XCFramework interface, and code inside a prebuilt framework can't tell whether the app is a Debug build. State what changes in the design if a check goes the other way.

## 4. Self-review before presenting

Read the whole draft and check each of these:

- **Zero code change:** does this ask the app to change code? If so, why can't it be automatic? Does it work the same in all three install options?
- **Layering:** does anything make the core import UIKit or SwiftProtobuf, or skip the capture → pipeline → store → dashboard order?
- **Three builds:** does it work as several modules and as one? Check imports, access levels and name clashes.
- **Host app safety:** what happens while Cerebro is off in Release? Is every new store capped?
- **Privacy:** does any path store or export a value before redaction?
- **Performance:** does new work stay off the request path and the main thread, stop at the cap, and format on open? Do live updates batch?
- **Design principles:** is anything speculative, a second path where one exists, or an abstraction with one user? Check against `.agents/rules/coding.md`.
- **Contradictions:** read each decision against the others and against the task list.
- **Shown code:** does every signature match the places that use it?
- **Overstated guarantees:** does "every request" really mean every request?
- **Standing docs:** does the plan update the docs that its change makes stale?
- **Numbering:** no `9a` criteria or task items.

## 5. Update standing docs as part of authoring

- Add a row to `.agents/plans/README.md`.
- Log the design calls in `.agents/memory/decisions.md`, with the date and the reasoning.
- Add a note to `.agents/memory/progress.md`, ending with "Nothing implemented: plan only" when that's true.

The file lives at `.agents/plans/PLAN-XX-<slug>.md`. It moves to `completed/` in its own implementation PR.

## Boundaries

- Never modify an existing plan file unprompted.
- Never start implementing while drafting a plan.
