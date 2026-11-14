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
├── .gitattributes             # keeps agent, CI and image folders out of source downloads
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
│                              # build-generator.sh; render-icon.sh and IconRenderer.swift, which render
│                              # the icon from CerebroIcon.swift
├── docs/                      # GUIDE.md for everything past setup
│   ├── screenshots/           # the README's screenshots and demo GIF
│   └── brand/                 # the icon, rendered: icon.svg and glyph.svg for any size, rounded/ PNGs up to
│                              # 256, app-icon/ at each iOS size up to 180, and social-preview.jpg for GitHub.
│                              # Kept small, because SPM downloads the whole history
├── Example/                   # example app using the package by local path
│   ├── traffic_map.json       # proto rules the build plugin turns into ProtoRule.generated
│   └── CerebroExample/        # App (delegates and the Cerebro.start call), Screens, Samples (each kind
│                              # of traffic and its helpers, and the files written for the Files tab),
│                              # Proto (generated .pb.swift), Resources (with the app icon)
├── Sources/
│   ├── CerebroCore/           # CaptureRuntime.swift wires the folders below together, and
│   │                          # PrivacyInfo.xcprivacy is the privacy manifest every install option ships
│   │   ├── HTTP/
│   │   │   ├── Capture/       # URLProtocol, config injection, background delegate proxy
│   │   │   ├── Pipeline/      # raw exchange, transaction builder, console logger; for event streams,
│   │   │   │                  # the SSE parser, assembler and processor
│   │   │   ├── Store/         # transaction store, cURL, JSON and HAR export
│   │   │   └── Models/        # transaction model, its metrics and its event stream
│   │   ├── Socket/
│   │   │   ├── Capture/       # WebSocket hooks, MonitoredNWConnection, ExternalNetworkBridge
│   │   │   ├── Pipeline/      # raw activity, activity builder
│   │   │   ├── Store/         # socket store
│   │   │   └── Models/        # socket connection model
│   │   ├── Shared/            # used by both
│   │   │   ├── Pipeline/      # body processing, decompression, redaction, capture backlog
│   │   │   ├── Store/         # ring buffer, snapshot observers, session archive
│   │   │   ├── Models/        # captured body, named value
│   │   │   └── Configuration/ # CerebroConfiguration, redaction rules, release gate
│   │   ├── Files/             # Files tab: roots and containment, listing, sizes, search, operations,
│   │   │                      # classification and reading for previews, folder watcher
│   │   └── Metrics/           # network path, interfaces, public IP, totals, connection quality, download progress
│   ├── Cerebro/
│   │   ├── Facade/            # Cerebro.start / stop / present
│   │   ├── Triggers/          # shake hook, floating trigger, PassthroughWindow, DashboardWindowManager,
│   │   │                      # CerebroIcon, the icon drawn in code
│   │   └── UI/                # tab bar shell, then one folder per screen holding its view controller,
│   │                          # view model and views (HTTPList, LogInspector, BodyViewer, SocketList,
│   │                          # SocketTimeline, ProtoConfig, SystemInfo, Files); Shared for the rest,
│   │                          # including DashboardTheme, where every colour comes from
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

In `CerebroCore`, a file goes in `HTTP/` or `Socket/` if only that traffic uses it, and in `Shared/` if both do. Inside those, it goes in the subfolder for its layer: `Capture/`, `Pipeline/`, `Store/` or `Models/`. `Files/` isn't traffic, so it has no layers.

An empty folder holds a `.gitkeep` so it gets committed. Delete that file when the folder gets real content.
