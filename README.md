# SimpleIDE

A lightweight desktop IDE for Windows built with Flutter and Riverpod. It delegates compiling, running, and tooling to the compilers and build systems already installed on your machine (`gcc`, `g++`, `python`, `java`, `dart`, `node`, `go`, `rustc`, `cmake`, `gradle`, `cargo`, etc.), with zero native Windows plugin dependencies.

## Features

### Code Editor
- **Syntax highlighting & folding**: 20+ languages via `re_editor` and `re_highlight`, line numbers, code folding, zoom (`Ctrl+=` / `Ctrl+-` / `Ctrl+0`), and word wrap (`Alt+Z`).
- **Code suggestions**: Context-aware autocomplete combining language snippets and identifiers from the active buffer.
- **Inline diagnostics**: Real-time syntax checks and compiler error/warning squiggles with gutter markers and a dedicated **Problems** tab.
- **Git gutter diff**: Live vertical indicators in the line-number gutter showing added, modified, and deleted lines relative to `HEAD`.
- **Editing tools**: Find & replace (`Ctrl+F` / `Ctrl+H`), go to line (`Ctrl+G`), toggle line comment (`Ctrl+/`), and right-click context actions.

### Project Search & Navigation
- **Global search & replace (`Ctrl+Shift+F`)**: Fast workspace-wide search with case-sensitive toggle (`Aa`), results grouped by file, one-click jump to line/column, and **Replace All**.
- **Quick Open & Command Palette**: Fuzzy file finder (`Ctrl+P`) and command palette (`Ctrl+Shift+P`).
- **Multi-document tabs**: Drag to reorder, middle-click to close, close others/saved/all, `Ctrl+Tab` cycling, and per-tab scroll position memory.

### Project & File Management
- **File explorer (`Ctrl+B`)**: Live file-system watcher, keyboard navigation, rename (`F2`), delete, copy path, and reveal in Windows File Explorer.
- **New Project wizard (`Ctrl+Shift+N`)**: Language presets (`C`, `C++`, `Python`, `Java`, `Dart`, `JavaScript`, `Go`, `Rust`, `Empty Project`) with optional build-tool scaffolding (`CMake`, `Makefile`, `Gradle`, `Maven`, `Cargo`, `Go Module`, `Dart Package`, `npm`) and live `PATH` toolchain checks.
- **Smart New File popup (`Ctrl+N`)**: Detects the project language and surfaces relevant templates first (e.g., `C++ Class` `.h`/`.hpp` + `.cpp` pair with optional `namespace`, Java classes/interfaces/enums, Python packages, etc.).
- **Always-on Auto-Save**: Automatically saves changes after a short idle debounce, on window focus loss, before every run, and on exit while preserving `CRLF`/`LF` line endings.

### Build, Run & Interactive Console
- **One-click Run (`F5`) & Stop (`Shift+F5`)**: Saves buffers, compiles if needed, and runs in the bottom console; `Shift+F5` terminates the entire process tree.
- **Build tool integration (`Ctrl+Shift+B`)**: Automatically detects `Gradle`, `Maven`, `CMake`, `Makefile`, `Cargo`, `Go`, `Dart`, and `npm` tasks in the workspace.
- **Per-project run configuration (`.simple_ide.json`)**: Override `runCommand`, `buildCommand`, working directory (`cwd`), and environment variables (`env`) per project via **Run → Project run config…**.
- **Interactive console (`Ctrl+J` / `` Ctrl+` ``)**: Streams `stdout`/`stderr`, forwards `stdin` (`Ctrl+Z` for EOF), makes compiler errors clickable to jump to the source line, and acts as an interactive shell with `cd` and command history when idle.

### Source Control & Agent CLI
- **Source Control (`Ctrl+Shift+G`)**: Inspect branch & working-tree status, stage/unstage files, commit, pull, push, and configure the `origin` remote.
- **Agent CLI Chat (`Ctrl+Shift+A`)**: Side-panel chat interface for running local CLI coding agents (`codex`, `claude`, `gemini`, `copilot`, or a custom command) inside the active project directory.

## Default Run Commands

Editable globally in **Settings → Run commands**, or overridden per project in `.simple_ide.json`:

| Language / Extension | Default Command |
|---|---|
| C (`.c`) | `gcc "${file}" -o "${out}"` → `"${out}"` |
| C++ (`.cpp`) | `g++ -std=c++17 "${file}" -o "${out}"` → `"${out}"` |
| Python (`.py`) | `python -u "${file}"` |
| Java (`.java`) | `java "${file}"` |
| Dart (`.dart`) | `dart run "${file}"` |
| JavaScript (`.js`) | `node "${file}"` |
| Go (`.go`) | `go run "${file}"` |
| Rust (`.rs`) | `rustc "${file}" -o "${out}"` → `"${out}"` |

C and C++ builds inject a small `stdout` unbuffering helper so interactive prompts (such as `printf` before `scanf`) appear immediately.

## Build & Test

```powershell
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

The release executable is output to `build\windows\x64\runner\Release\simple_ide.exe`. Because the project uses only pure-Dart packages, Windows Developer Mode is not required.

## Architecture

The codebase follows a feature-first SOLID layout:

```text
lib/
  app/                  Application shell, controller, top/status bars, activity rail, palette
  features/
    agent/              Local CLI agent runner and chat panel
    diagnostics/        Compiler output parser, syntax checker, inline & gutter layers, problems view
    editor/             Document model, editor pane, code suggestions, find panel, git gutter, tabs
    explorer/           Workspace tree, file watcher, explorer panel
    git/                Git CLI service and source control panel
    project/            New project/file wizards, template planners, folder picker, .simple_ide.json
    runner/             Process runner, language & build-tool detectors, console buffer & UI
    search/             Workspace search/replace engine and sidebar panel
    settings/           Persistent IDE settings, toolchain detection, settings dialog
    welcome/            Start page and empty editor state
  shared/
    tokens.dart         Design tokens (colors, typography, syntax theme)
    widgets/            Reusable UI primitives (buttons, dialogs, splitters, badges, status dots)
test/
  core_test.dart        Unit and compiler/git integration tests
  widget_test.dart      Widget and layout overflow tests
```
