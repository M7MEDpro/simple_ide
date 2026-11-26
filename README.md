# SimpleIDE

A lightweight desktop IDE built with Flutter for Windows. It implements the six features from the project proposal and hands all compiling and running to the toolchains already installed on the machine (gcc, g++, python, java, node, and others).

## Features

| Proposal feature | What it does |
|---|---|
| Code editor | Syntax highlighting for 20+ languages, line numbers, code folding, find and replace (regex and match case), toggle comment (Ctrl+/), go to line (Ctrl+G), zoom, word wrap, right-click menu |
| File explorer | Folder tree that updates live from disk, keyboard navigation, new file or folder, rename (F2), delete, copy path, reveal in File Explorer, open a console in a folder |
| Multi-document tabs | Drag to reorder, middle-click to close, close others/saved/all, Ctrl+Tab to switch, unsaved dot, per-tab scroll position kept |
| One-click run | F5 or the Run button saves every buffer, then builds and runs the file. Shift+F5 stops the whole process tree |
| Interactive console | Live stdout/stderr, input goes to the program's stdin, Ctrl+Z sends end of input, compiler errors are clickable and jump to the line, runs shell commands when idle (with `cd` and command history) |
| Auto-save | Writes 0.8 s after you stop typing (configurable), when the window loses focus, before every run, and on exit. Keeps CRLF/LF line endings |

Also included: quick open (Ctrl+P), command palette (Ctrl+Shift+P), settings for editable run commands per extension, session restore (last folder and tabs), and a start view that lists which compilers are on PATH.

## Run commands

Defaults (editable in Settings > Run commands):

| Extension | Command |
|---|---|
| `.c` | `gcc "${file}" -o "${out}"`, then `"${out}"` |
| `.cpp` | `g++ -std=c++17 "${file}" -o "${out}"`, then `"${out}"` |
| `.py` | `python -u "${file}"` |
| `.java` | `java "${file}"` |
| `.js` | `node "${file}"` |

C and C++ builds link a small helper that turns off stdout buffering, so prompts like `printf("Enter n: ")` appear before `scanf` waits for input.

## Build

```powershell
flutter pub get
flutter test
flutter build windows --release
```

The app is written to `build\windows\x64\runner\Release\simple_ide.exe`. It uses no native plugins, so Windows Developer Mode is not needed.

## Code layout

```
lib/
  core/      state and logic: documents, workspace, runner, console, settings
  ui/        widgets: shell, bars, explorer, tabs, editor, console, dialogs
  theme/     colour and type tokens
test/        unit tests and real compiler integration tests
```
