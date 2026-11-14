---
name: release
description: Release Cerebro by merging develop into main, after which release.yml tests, updates the version, tags and publishes. Use when the owner says "release", "cut a release" or "merge to main".
---

# Release: develop → main

A release happens when `develop` is merged into `main`. `.github/workflows/release.yml` does the rest. This skill covers only the preflight, the PR and confirming the result.

The workflow:

1. Works out the version from the commits since the last tag with `Scripts/next-version.sh`. With no `feat`, `fix`, breaking commit or `Release-As` footer, it stops and nothing is released.
2. Runs all of `ci.yml`. Any failure stops the release with nothing changed.
3. Updates the version with `Scripts/set-version.sh`, adds the release's section to `CHANGELOG.md` with `Scripts/update-changelog.sh`, and builds the XCFrameworks.
4. Commits `chore(release): vX.Y.Z`, tags `vX.Y.Z`, and pushes both together.
5. Publishes the GitHub Release with the XCFrameworks, that version's install lines and its `CHANGELOG.md` section.
6. Merges `main` back into `develop`.

Hard rules: never edit versions or `CHANGELOG.md`, or create release tags, by hand. Never force-push. Never push to CocoaPods trunk: only the owner does, by hand, until it goes read-only on December 2, 2026. The owner merges every PR.

## Procedure

1. **Preflight** on a clean, current `develop`: every plan in this release is ticked in `.agents/plans/README.md`, and CI is green on `develop`.
2. **Context sync:** run the `context-sync` skill so the docs match the code being shipped. Stop for the owner to merge.
3. **Release PR:** open `develop` → `main`, titled `chore: release develop`, with a summary of what ships and the version `Scripts/next-version.sh` predicts. Stop for the owner to merge it with a merge commit, never a squash.
4. **Confirm** after the merge: the `Release` workflow succeeds, the GitHub Release shows the install lines for this version and the same changes as its new `CHANGELOG.md` section, and has `Cerebro`, `CerebroProto` and `SwiftProtobuf` `.xcframework.zip` assets plus `cerebro-proto-gen.zip`, and `develop` contains the `chore(release)` commit. From PLAN-03 on it also needs the `cerebro-proto-gen` binary. Report the release URL.

## When it needs a hand

- **No release, and you expected one:** there was no `feat`, `fix` or breaking commit since the last tag. A `chore:` or `docs:` merge makes no release on purpose.
- **Tests failed:** nothing changed. Fix it through a normal PR into `develop`, then merge `develop` into `main` again.
- **Publishing failed after the push:** the tag exists without a release, and rerunning the job can't recreate the tag. Check out the tag, which already has its `CHANGELOG.md` section, and run `Scripts/build-xcframework.sh` and the generator build. Then run the workflow's publish step by hand: `Scripts/release-notes.sh` first, then its `gh release create` command.
- **The back-merge failed:** bring `main` into `develop` through a PR.
- **`main` or `develop` gets branch protection:** `GITHUB_TOKEN` can't push past it. Add a fine-grained PAT as the repo secret `RELEASE_TOKEN`, with Contents and Workflows read and write. The workflow uses it automatically.
