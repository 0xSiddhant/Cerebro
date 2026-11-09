# Project Structure

```
Cerebro/
├── AGENTS.md                  # instructions for any coding agent
├── CLAUDE.md                  # Claude-specific notes; imports AGENTS.md
├── README.md                  # setup, configuration, what Cerebro can't capture
├── LICENSE                    # MIT
├── Package.swift              # SPM targets and products
├── Package.resolved           # pins the SwiftProtobuf version the XCFramework ships
├── Cerebro.podspec            # Git-sourced; subspecs Core, UI, Proto
├── Cerebro.xcodeproj          # framework targets; builds the XCFrameworks
├── .swift-format              # formatting, crash paths and public docs
├── .swiftlint.yml             # code quality; a contributor tool, never a dependency
├── .swiftpm/xcode/            # package workspace, so xcodebuild can reach the package
├── .agents/
│   ├── context/               # architecture, tech stack, this file, notes
│   ├── plans/                 # plan index, one file per open plan
│   ├── rules/                 # git.md, coding.md
│   └── skills -> ../.claude/skills
├── .claude/skills/            # build-and-test, podspec-lint, build-xcframework,
│                              # release, new-plan, context-sync
├── .githooks/                 # pre-commit hook; a contributor tool, enabled once per clone
├── .github/workflows/         # ci.yml on PRs and develop; release.yml when develop merges into main
├── Scripts/                   # build-xcframework.sh, next-version.sh, set-version.sh, release-notes.sh;
│                              # build-generator.sh arrives in PLAN-03
├── Example/                   # example app using the package by local path
│   └── traffic_map.json       # proto mappings; PLAN-03 wires it to the build plugin
├── Sources/
│   ├── CerebroCore/           # CaptureRuntime.swift wires the folders below together
│   │   ├── HTTP/              # URLProtocol, config injection, transaction model, builder and store;
│   │   │                      # background delegate proxy, persistence and export in later plans
│   │   ├── Socket/            # WebSocket hooks, MonitoredNWConnection, ExternalNetworkBridge,
│   │   │                      # socket model, builder and store
│   │   ├── Shared/            # used by both: body processing, redaction, ring buffer
│   │   ├── Metrics/           # PLAN-04: NWPathMonitor, getifaddrs, public IP
│   │   └── Configuration/
│   ├── Cerebro/
│   │   ├── Facade/            # Cerebro.start / stop / present
│   │   ├── Triggers/          # shake hook, floating trigger, PassthroughWindow, DashboardWindowManager
│   │   └── UI/                # tab bar shell, then one folder per screen holding its view controller,
│   │                          # view model and views (HTTPList, LogInspector, BodyViewer, SocketList,
│   │                          # SocketTimeline); Shared for the rest
│   ├── CerebroProto/          # proto rules and decoder
│   └── CerebroProtoGenerator/ # reads traffic_map.json and .pb.swift files, writes ProtoRule.generated
├── Plugins/
│   └── CerebroProtoPlugin/    # SPM build-tool plugin that runs the generator
└── Tests/
    ├── CerebroCoreTests/
    ├── CerebroTests/
    ├── CerebroProtoTests/
    └── CerebroProtoGeneratorTests/
```

In `CerebroCore`, a file goes in `HTTP/` or `Socket/` if only that traffic uses it, and in `Shared/` if both do. Each of the three stays flat.

An empty folder holds a `.gitkeep` so it gets committed. Delete that file when the folder gets real content.
