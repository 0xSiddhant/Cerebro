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
├── .swiftpm/xcode/            # package workspace, so xcodebuild can reach the package
├── .agents/
│   ├── context/               # architecture, tech stack, this file
│   ├── memory/                # progress, decisions, history
│   ├── plans/                 # plan index, one file per plan, completed/
│   ├── rules/                 # git.md, coding.md
│   └── skills -> ../.claude/skills
├── .claude/skills/            # build-and-test, podspec-lint, build-xcframework,
│                              # release, new-plan, context-sync
├── .github/workflows/         # ci.yml on PRs and develop; release.yml when develop merges into main
├── Scripts/                   # build-xcframework.sh, next-version.sh, set-version.sh, release-notes.sh;
│                              # build-generator.sh arrives in PLAN-03
├── Example/                   # example app using the package by local path
│   └── traffic_map.json       # proto mappings; PLAN-03 wires it to the build plugin
├── Sources/
│   ├── CerebroCore/
│   │   ├── Capture/           # URLProtocol, config injection, background delegate proxy,
│   │   │                      # WebSocket hooks, MonitoredNWConnection, ExternalNetworkBridge
│   │   ├── Pipeline/          # decompression, pretty JSON, redaction
│   │   ├── Store/             # ring buffer, session persistence, export
│   │   ├── Metrics/           # NWPathMonitor, getifaddrs, byte counting, public IP
│   │   ├── Models/
│   │   └── Configuration/
│   ├── Cerebro/
│   │   ├── Facade/            # Cerebro.start / stop / present
│   │   ├── Triggers/          # shake hook, floating trigger, PassthroughWindow, DashboardWindowManager
│   │   └── UI/                # tab bar shell, HTTP list, Log Inspector, Sockets, Proto Config, System Info
│   ├── CerebroProto/          # proto rules and decoder
│   └── CerebroProtoGenerator/ # reads traffic_map.json and .pb.swift files, writes ProtoRule.generated
├── Plugins/
│   └── CerebroProtoPlugin/    # SPM build-tool plugin that runs the generator
└── Tests/
    ├── CerebroCoreTests/
    ├── CerebroProtoTests/
    └── CerebroProtoGeneratorTests/
```

An empty folder holds a `.gitkeep` so it gets committed. Delete that file when the folder gets real content.
