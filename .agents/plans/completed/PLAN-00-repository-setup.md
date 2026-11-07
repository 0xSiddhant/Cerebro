# PLAN-00 — Repository setup

## Goal

A repository that builds in all three distribution shapes from the first commit, with no capture code yet. Every later plan lands through a PR into this setup, and the difference between several modules and one module never surprises a release.

## Gate

Special git rule, this plan only: the initial commit lands directly on `main`. The owner reviews the git rules before that commit.

## Scope

**In:** git, SPM, CocoaPods, XCFramework build, GitHub Actions, Example app, folder structure, agent setup, initial commit.

**Out:** any capture, pipeline, store or dashboard behaviour. `Cerebro.start`, `stop` and `present` exist as empty placeholders, so the module boundaries are compiled and tested from day one.

## Decisions & reasoning

### Placeholders that cross every module boundary

Each target needs a source file anyway, so the placeholders do real work: `Cerebro.start` takes the core's `CerebroConfiguration`, and `CerebroProto` extends it. That makes every channel prove its imports resolve.

### Additions the spec doesn't list

- `.agents/context`, `.agents/memory` and `.agents/plans`, following the owner's bifrost repo.
- Real skill files in `.claude/skills`, with `.agents/skills` as a symlink, also following bifrost. The spec's `.agents/skills/` path still resolves, and Claude Code discovers the skills.
- `new-plan` and `context-sync` skills, on top of the spec's four.
- A committed `Package.resolved` and `.swiftpm/xcode/package.xcworkspace`.
- CI also runs on pull requests, because the git rules require CI green before a merge.
- The XCFramework build runs on every push, not only on tags, because the spec requires CI to build all three shapes from Plan 0.
- `Scripts/release-notes.sh`, so each GitHub Release gives that version's exact SPM and CocoaPods lines, at the owner's request. The release workflow also fails if the tag doesn't match the podspec.

`memory/decisions.md` records the reasoning, and the build settings these led to.

## Public API

Placeholders only: `Cerebro.start(_:)`, `Cerebro.stop()`, `Cerebro.present()`, `CerebroConfiguration`, `ProtoRule`. PLAN-01 and PLAN-03 give them behaviour.

## Task checklist

- [x] Git: `main` as default, `.gitignore` for Xcode, SPM and CocoaPods output, MIT `LICENSE`
- [x] SPM: `Package.swift` with `CerebroCore`, `Cerebro`, `CerebroProto` and their test targets, iOS 16
- [x] CocoaPods: Git-sourced `Cerebro.podspec` with `Core`, `UI` and `Proto` subspecs that passes `pod lib lint`
- [x] XCFramework: `Cerebro.xcodeproj` compiling the same sources, and `Scripts/build-xcframework.sh`
- [x] GitHub Actions: `ci.yml` and `release.yml`
- [x] Example app with URLSession, WebSocket, NWConnection and protobuf traffic, and a placeholder `traffic_map.json`
- [x] Folder structure, with a `.gitkeep` in each empty folder
- [x] Agent setup: `AGENTS.md`, `CLAUDE.md`, `.agents/rules/git.md`, skills
- [x] Initial commit, with a body explaining why the repository is laid out this way

## Acceptance criteria

1. Package tests pass on an iOS simulator.
2. `pod lib lint Cerebro.podspec` passes.
3. `Scripts/build-xcframework.sh` builds all three XCFrameworks, and a client compiles against them.
4. The Example app builds, runs and completes all four kinds of traffic.
5. A host app completes the same traffic with each of the three install options.
6. SPM resolves `exact: "X.Y.Z"` and CocoaPods resolves `:tag => 'vX.Y.Z'` from a `vX.Y.Z` tag.
7. Every folder in the spec's layout exists.
8. No build output is committed.

## Test checklist

- [x] `xcodebuild test` on the `Cerebro-Package` scheme, iPhone 17 simulator
- [x] `pod lib lint`, including each subspec alone
- [x] Client compiled against the XCFrameworks, then linked and run on a simulator
- [x] Example app run on a simulator
- [x] Example sources run on a simulator through SPM, a pod pulled from a tag, and embedded XCFrameworks
- [x] `exact:` resolved against a `v`-prefixed tag in a throwaway repo
- [ ] GitHub Actions run on a real push, which needs the owner to push
