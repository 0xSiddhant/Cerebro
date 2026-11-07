# Git Rules (non-negotiable)

## Branches

- `main` is the default branch. Changes reach it only through a pull request with CI green, and it is never force-pushed.
- One branch per plan: `plan/<number>-<slug>`, e.g. `plan/1-http-capture`.
- Only Plan 0's initial commit lands directly on `main`.

A plan file may declare an explicit, scoped exception to these rules. The plan file wins for that plan only.

## Flow for implementing a plan

1. `git checkout main && git pull`
2. `git checkout -b plan/<number>-<slug>`
3. Implement in small commits, one task each.
4. Run the `build-and-test` skill. It must pass.
5. Push and open a PR into `main`. The body says what the plan delivered, any deviations and why, and the test evidence.
6. CI must be green. The owner reviews and merges. Never self-merge.
7. Update `.agents/memory/progress.md` in the same PR.

## Commits

Conventional Commits, valid under commitlint's `@commitlint/config-conventional` with a 72-character header.

- Format: `<type>(<scope>): <subject>`. The scope is optional.
- Types: `feat`, `fix`, `chore`, `docs`, `test`, `ci`, `refactor`.
- Scopes, when used: `core`, `ui`, `proto`, `generator`, `example`, `ci`, `docs`.
- Keep every message concise: a short subject, and a body of a few lines at most.
- Header: 72 characters at most, including the type and scope.
- Subject: imperative, starts lowercase, no trailing period. Identifiers keep their case, e.g. `capture URLSession traffic`.
- Body: explains why, not what. It follows a blank line, and its lines are 100 characters at most.
- No `Co-authored-by` trailer or other co-author info unless the owner explicitly asks for one on that commit. This holds for commits made by AI agents too.
- Small commits, one task each.
- Never commit build output: `.build`, `DerivedData`, `Pods`, `*.xcframework`.

Example:

```
feat(core): cap stored bodies at 1 MB

Large bodies, not request count, cause out-of-memory crashes.
```

## Releases

Releases are `vX.Y.Z` tags on `main`. A tag triggers the XCFramework build and the GitHub Release. SPM consumes the tag with `exact: "X.Y.Z"`, and CocoaPods with `:tag => 'vX.Y.Z'`. The `release` skill has the steps.
