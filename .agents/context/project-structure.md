# Project Structure

```
Cerebro/
├── AGENTS.md                  # instructions for any coding agent
├── CLAUDE.md                  # Claude-specific notes; imports AGENTS.md
├── README.md                  # overview, screenshots, install and first steps
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
│                              # build-generator.sh
├── docs/                      # GUIDE.md for everything past setup, and the README's screenshots
├── Example/                   # example app using the package by local path
│   └── traffic_map.json       # proto rules the build plugin turns into ProtoRule.generated
├── Sources/
│   ├── CerebroCore/           # CaptureRuntime.swift wires the folders below together
│   │   ├── HTTP/
│   │   │   ├── Capture/       # URLProtocol, config injection; background delegate proxy in PLAN-05
│   │   │   ├── Pipeline/      # raw exchange, transaction builder, console logger
│   │   │   ├── Store/         # transaction store, cURL; persistence and export in later plans
│   │   │   └── Models/        # transaction model and its metrics
│   │   ├── Socket/
│   │   │   ├── Capture/       # WebSocket hooks, MonitoredNWConnection, ExternalNetworkBridge
│   │   │   ├── Pipeline/      # raw activity, activity builder
│   │   │   ├── Store/         # socket store
│   │   │   └── Models/        # socket connection model
│   │   ├── Shared/            # used by both
│   │   │   ├── Pipeline/      # body processing, decompression, redaction
│   │   │   ├── Store/         # ring buffer, snapshot observers
│   │   │   ├── Models/        # captured body, named value
│   │   │   └── Configuration/ # CerebroConfiguration, redaction rules, release gate
│   │   └── Metrics/           # PLAN-04: NWPathMonitor, getifaddrs, public IP
│   ├── Cerebro/
│   │   ├── Facade/            # Cerebro.start / stop / present
│   │   ├── Triggers/          # shake hook, floating trigger, PassthroughWindow, DashboardWindowManager
│   │   └── UI/                # tab bar shell, then one folder per screen holding its view controller,
│   │                          # view model and views (HTTPList, LogInspector, BodyViewer, SocketList,
│   │                          # SocketTimeline, ProtoConfig); Shared for the rest
│   ├── CerebroProto/          # proto rules and decoder
│   ├── CerebroProtoGenerator/ # the generator executable
│   └── CerebroProtoGeneratorCore/ # reads traffic_map.json and .pb.swift files, writes ProtoRule.generated
├── Plugins/
│   └── CerebroProtoPlugin/    # SPM build-tool plugin that runs the generator
└── Tests/
    ├── CerebroCoreTests/
    ├── CerebroTests/
    ├── CerebroProtoTests/
    └── CerebroProtoGeneratorTests/
```

In `CerebroCore`, a file goes in `HTTP/` or `Socket/` if only that traffic uses it, and in `Shared/` if both do. Inside those, it goes in the subfolder for its layer: `Capture/`, `Pipeline/`, `Store/` or `Models/`.

An empty folder holds a `.gitkeep` so it gets committed. Delete that file when the folder gets real content.
