# Git Rules (non-negotiable)

## Branches

- `develop` is the integration branch. All implementation lands here through a pull request with CI green.
- `main` holds released code. It only receives `develop`, through a pull request, and it is never force-pushed. The release workflow's `chore(release)` commit is the one exception.
- Implementation branches start from the latest `develop`:
  - one per plan: `plan/<number>-<slug>`, e.g. `plan/1-http-capture`
  - other work: `<type>/<slug>`, e.g. `fix/redaction-crash`

A plan file may declare an explicit, scoped exception to these rules. The plan file wins for that plan only.

## Flow for implementing a plan

1. `git checkout develop && git pull`
2. `git checkout -b plan/<number>-<slug>`
3. Implement in small commits, one task each.
4. Run the `build-and-test` skill. It must pass.
5. Push and open a PR into `develop`. The body says what the plan delivered, any deviations and why, and the test evidence.
6. CI must be green. The owner reviews and merges. Never self-merge.
7. Update `.agents/memory/progress.md` in the same PR.

## Commits

Conventional Commits, valid under commitlint's `@commitlint/config-conventional` with a 72-character header.

- Format: `<type>(<scope>): <subject>`. The scope is optional.
- Types: `feat`, `fix`, `chore`, `docs`, `test`, `ci`, `refactor`.
- Scopes, when used: `core`, `ui`, `proto`, `generator`, `example`, `ci`, `docs`, `release`.
- Keep every message concise: a short subject, and a body of a few lines at most.
- Header: 72 characters at most, including the type and scope.
- Subject: imperative, starts lowercase, no trailing period. Identifiers keep their case, e.g. `capture URLSession traffic`.
- Body: explains why, not what. It follows a blank line, and its lines are 100 characters at most.
- No `Co-authored-by` trailer or other co-author info unless the owner explicitly asks for one on that commit. This holds for commits made by AI agents too.
- Small commits, one task each.
- Never commit build output: `.build`, `DerivedData`, `Pods`, `*.xcframework`.
- A squashed PR keeps only its title, so give every PR a title that follows these rules. The release reads it.

Example:

```
feat(core): cap stored bodies at 1 MB

Large bodies, not request count, cause out-of-memory crashes.
```

## Releases

A release happens when `develop` is merged into `main`. Never edit versions or create release tags by hand.

1. Open a PR from `develop` into `main`. The owner merges it with a merge commit, never a squash, because the release reads the commits since the last tag.
2. `.github/workflows/release.yml` works out the version: `feat` is a minor bump, `fix` is a patch, and `!` or `BREAKING CHANGE` is a major, or a minor while the major version is 0. A `Release-As: X.Y.Z` footer forces that version.
3. Every CI job must pass. Only then does it update the version, build the XCFrameworks, commit `chore(release): vX.Y.Z`, tag `vX.Y.Z`, publish the GitHub Release, and merge `main` back into `develop`.

A merge with no `feat`, `fix` or breaking commit makes no release.

SPM consumes a release with `exact: "X.Y.Z"`, and CocoaPods with `:tag => 'vX.Y.Z'`. The `release` skill has the steps.
