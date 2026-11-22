import 'dart:io';

import 'package:path/path.dart' as p;

/**
 * A project-level build, run, or test command detected from workspace files.
 */
class BuildTask {
  const BuildTask({
    required this.tool,
    required this.label,
    required this.command,
  });

  final String tool;
  final String label;
  final String command;
}

/**
 * Inspects [workspaceRoot] (non-recursively) and returns tasks for any
 * recognized build tool: Gradle, Maven, CMake, Make, Cargo, Go, npm/yarn/pnpm/bun,
 * Dart/Flutter, .NET, and Python.
 *
 * @param workspaceRoot root directory of the open project
 * @return ordered list of detected build tasks, empty when none apply
 */
List<BuildTask> detectBuildTasks(String workspaceRoot) {
  final dir = Directory(workspaceRoot);
  if (!dir.existsSync()) return const [];
  final names = <String>{};
  try {
    for (final e in dir.listSync(followLinks: false)) {
      names.add(p.basename(e.path).toLowerCase());
    }
  } catch (_) {
    return const [];
  }

  final tasks = <BuildTask>[];

  // Gradle
  if (names.contains('build.gradle') || names.contains('build.gradle.kts')) {
    final exe = Platform.isWindows && names.contains('gradlew.bat')
        ? 'gradlew.bat'
        : (!Platform.isWindows && names.contains('gradlew') ? './gradlew' : 'gradle');
    tasks.addAll([
      BuildTask(tool: 'Gradle', label: 'Run', command: '$exe run'),
      BuildTask(tool: 'Gradle', label: 'Build', command: '$exe build'),
      BuildTask(tool: 'Gradle', label: 'Test', command: '$exe test'),
    ]);
  }

  // Maven
  if (names.contains('pom.xml')) {
    final exe = Platform.isWindows && names.contains('mvnw.cmd')
        ? 'mvnw.cmd'
        : (!Platform.isWindows && names.contains('mvnw') ? './mvnw' : 'mvn');
    tasks.addAll([
      BuildTask(tool: 'Maven', label: 'Compile', command: '$exe compile'),
      BuildTask(tool: 'Maven', label: 'Run (exec:java)', command: '$exe compile exec:java'),
      BuildTask(tool: 'Maven', label: 'Test', command: '$exe test'),
    ]);
  }

  // CMake
  if (names.contains('cmakelists.txt')) {
    tasks.addAll([
      const BuildTask(tool: 'CMake', label: 'Configure & Build', command: 'cmake -B build && cmake --build build'),
      const BuildTask(tool: 'CMake', label: 'Build', command: 'cmake --build build'),
    ]);
  }

  // Make
  if (names.contains('makefile') || names.contains('gnumakefile')) {
    tasks.addAll([
      const BuildTask(tool: 'Make', label: 'Build (make)', command: 'make'),
      const BuildTask(tool: 'Make', label: 'Clean', command: 'make clean'),
    ]);
  }

  // Cargo (Rust)
  if (names.contains('cargo.toml')) {
    tasks.addAll([
      const BuildTask(tool: 'Cargo', label: 'Run', command: 'cargo run'),
      const BuildTask(tool: 'Cargo', label: 'Build', command: 'cargo build'),
      const BuildTask(tool: 'Cargo', label: 'Test', command: 'cargo test'),
    ]);
  }

  // Go
  if (names.contains('go.mod')) {
    tasks.addAll([
      const BuildTask(tool: 'Go', label: 'Run', command: 'go run .'),
      const BuildTask(tool: 'Go', label: 'Build', command: 'go build ./...'),
      const BuildTask(tool: 'Go', label: 'Test', command: 'go test ./...'),
    ]);
  }

  // Node (npm / pnpm / yarn / bun)
  if (names.contains('package.json')) {
    final pm = names.contains('bun.lockb') || names.contains('bun.lock')
        ? 'bun'
        : names.contains('pnpm-lock.yaml')
            ? 'pnpm'
            : names.contains('yarn.lock')
                ? 'yarn'
                : 'npm';
    tasks.addAll([
      BuildTask(tool: pm, label: 'Start', command: '$pm start'),
      BuildTask(tool: pm, label: 'Build', command: '$pm run build'),
      BuildTask(tool: pm, label: 'Test', command: '$pm test'),
    ]);
  }

  // Dart / Flutter
  if (names.contains('pubspec.yaml')) {
    var isFlutter = false;
    try {
      final pub = File(p.join(workspaceRoot, 'pubspec.yaml')).readAsStringSync();
      isFlutter = pub.contains('sdk: flutter');
    } catch (_) {}
    if (isFlutter) {
      tasks.addAll([
        const BuildTask(tool: 'Flutter', label: 'Run', command: 'flutter run'),
        const BuildTask(tool: 'Flutter', label: 'Test', command: 'flutter test'),
      ]);
    } else {
      tasks.addAll([
        const BuildTask(tool: 'Dart', label: 'Run', command: 'dart run'),
        const BuildTask(tool: 'Dart', label: 'Test', command: 'dart test'),
      ]);
    }
  }

  // .NET
  if (names.any((n) => n.endsWith('.csproj') || n.endsWith('.sln'))) {
    tasks.addAll([
      const BuildTask(tool: '.NET', label: 'Run', command: 'dotnet run'),
      const BuildTask(tool: '.NET', label: 'Build', command: 'dotnet build'),
      const BuildTask(tool: '.NET', label: 'Test', command: 'dotnet test'),
    ]);
  }

  // Python project
  if (names.contains('pyproject.toml') || names.contains('requirements.txt')) {
    tasks.add(const BuildTask(tool: 'Python', label: 'Test (pytest)', command: 'pytest'));
  }

  return tasks;
}
