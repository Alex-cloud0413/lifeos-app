# Life · OS

**Project-centered execution, with local agents helping organize and move work forward.**

[中文](README.md) · [Build and iCloud setup](docs/building.md) · [Agent workflow](docs/agent-workflow.md) · [CLI reference](docs/cli.md)

Life · OS is a native personal task app for macOS and iOS. Its structure is **Area → Project → Task → Nested subtasks**. Start with the work you want to advance; add dates when useful.

People work in the app. Local agents use a CLI to inspect the same structure, classify incoming tasks, break work into steps, and update progress. Changes pass through the app's command rules and enter the same history and iCloud sync pipeline.

## Features

- Projects within long-term areas; nested subtasks, sibling reordering, and subtree moves.
- Rich-text notes with a full-screen editor, progress, status, tags, priorities, and optional dates.
- A local CLI with JSON output, idempotent requests, revision checks, batch actions, templates, and undo.
- CloudKit private database sync using **your own** Apple developer configuration, with offline storage on each device.
- Search, filters, boards, calendar views, notes, archives, trash, Mac quick capture, iOS sharing, and Shortcuts.
- A monochrome interface with an optional subtle paper texture.

There is no embedded AI model or required model API key. Use an agent that can run local commands. The app does not parse natural language and intentionally omits reminders, habit tracking, Pomodoro timers, countdowns, Eisenhower matrices, and fixed retrospective templates.

## Try the local preview

Requires macOS and full Xcode with Swift 6 (Xcode 16 or newer). The UI is currently primarily Chinese. Deployment targets are macOS 14 and iOS/iPadOS 17.

```sh
git clone https://github.com/Alex-cloud0413/lifeos-app.git
cd lifeos-app
swift test
zsh scripts/build.sh preview
open build/PreviewDerivedData/Build/Products/Preview/Dayline.app
```

Preview uses a local database and never connects to iCloud. For device builds and sync, follow [the setup guide](docs/building.md). This repository provides development source, not a universally installable signed application. No personal tasks, Apple certificates, provisioning profiles, or developer accounts are included.

On Mac, enable the local agent connection in Settings, then run `./build/lifeos help`. Custom signed builds need `LIFEOS_BUNDLE_ID` set for the CLI, or an explicit `--socket` path. See the [agent workflow](docs/agent-workflow.md) and [architecture](docs/architecture.md).

The Xcode project and core modules retain the early internal name `Dayline`. There are no third-party Swift Package dependencies. See [validation scope](docs/verification.md), [contributing](CONTRIBUTING.md), and [security](SECURITY.md).

Licensed under [MIT](LICENSE). Fork it and adapt it to how you work.
