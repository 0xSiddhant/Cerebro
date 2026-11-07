---
name: podspec-lint
description: Lint Cerebro.podspec, which compiles every subspec as one module. Use when sources move, a framework dependency changes, the podspec is edited, or as a step of build-and-test.
---

# Podspec lint

```sh
pod lib lint Cerebro.podspec
```

The lint builds the default subspecs together, then `Core`, `UI` and `Proto` one at a time, all inside a single `Cerebro` module. So it catches what SPM can't:

- two files or types with the same name across `Sources/CerebroCore` and `Sources/Cerebro`
- `Cerebro/Core` reaching for `UI` code, since the lint builds it alone
- a system framework a subspec uses but doesn't declare

Never run `pod trunk push` or `pod repo push`. The pod is consumed from Git, and trunk goes read-only on December 2, 2026.

`Proto` pins SwiftProtobuf to the same range as `Package.swift`. Change them together.
