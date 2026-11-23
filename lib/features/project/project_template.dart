import 'dart:io';

import 'package:path/path.dart' as p;

/**
 * Language and build-tool preset offered in the New Project dialog.
 */
class ProjectTemplate {
  const ProjectTemplate({
    required this.id,
    required this.name,
    required this.subtitle,
    this.entryFile,
    this.toolchainCommand,
    this.starterCode = '',
    this.buildTools = const ['Single file'],
  });

  final String id;
  final String name;
  final String subtitle;
  final String? entryFile;
  final String? toolchainCommand;
  final String starterCode;
  final List<String> buildTools;
}

/**
 * Built-in project templates matching the languages SimpleIDE can run.
 */
const List<ProjectTemplate> projectTemplates = [
  ProjectTemplate(
    id: 'c',
    name: 'C',
    subtitle: 'Console application (GCC)',
    entryFile: 'main.c',
    toolchainCommand: 'gcc',
    buildTools: ['Single file', 'CMake', 'Makefile'],
    starterCode: '#include <stdio.h>\n\n'
        'int main(void) {\n'
        '    printf("Hello, World!\\n");\n'
        '    return 0;\n'
        '}\n',
  ),
  ProjectTemplate(
    id: 'cpp',
    name: 'C++',
    subtitle: 'Console application (G++)',
    entryFile: 'main.cpp',
    toolchainCommand: 'g++',
    buildTools: ['Single file', 'CMake', 'Makefile'],
    starterCode: '#include <iostream>\n\n'
        'int main() {\n'
        '    std::cout << "Hello, World!" << std::endl;\n'
        '    return 0;\n'
        '}\n',
  ),
  ProjectTemplate(
    id: 'python',
    name: 'Python',
    subtitle: 'Python script',
    entryFile: 'main.py',
    toolchainCommand: 'python',
    starterCode: 'def main():\n'
        '    print("Hello, World!")\n\n\n'
        'if __name__ == "__main__":\n'
        '    main()\n',
  ),
  ProjectTemplate(
    id: 'java',
    name: 'Java',
    subtitle: 'Java application',
    entryFile: 'Main.java',
    toolchainCommand: 'java',
    buildTools: ['Single file', 'Gradle', 'Maven'],
    starterCode: 'public class Main {\n'
        '    public static void main(String[] args) {\n'
        '        System.out.println("Hello, World!");\n'
        '    }\n'
        '}\n',
  ),
  ProjectTemplate(
    id: 'dart',
    name: 'Dart',
    subtitle: 'Dart console application',
    entryFile: 'main.dart',
    toolchainCommand: 'dart',
    buildTools: ['Single file', 'Dart Package'],
    starterCode: 'void main() {\n'
        '  print(\'Hello, World!\');\n'
        '}\n',
  ),
  ProjectTemplate(
    id: 'js',
    name: 'JavaScript',
    subtitle: 'Node.js script',
    entryFile: 'index.js',
    toolchainCommand: 'node',
    buildTools: ['Single file', 'npm'],
    starterCode: 'console.log("Hello, World!");\n',
  ),
  ProjectTemplate(
    id: 'go',
    name: 'Go',
    subtitle: 'Go module entry file',
    entryFile: 'main.go',
    toolchainCommand: 'go',
    buildTools: ['Single file', 'Go Module'],
    starterCode: 'package main\n\n'
        'import "fmt"\n\n'
        'func main() {\n'
        '    fmt.Println("Hello, World!")\n'
        '}\n',
  ),
  ProjectTemplate(
    id: 'rust',
    name: 'Rust',
    subtitle: 'Rust source file',
    entryFile: 'main.rs',
    toolchainCommand: 'rustc',
    buildTools: ['Single file', 'Cargo'],
    starterCode: 'fn main() {\n'
        '    println!("Hello, World!");\n'
        '}\n',
  ),
  ProjectTemplate(
    id: 'empty',
    name: 'Empty Project',
    subtitle: 'Blank folder with no starter files',
  ),
];

/**
 * Returns the default parent directory where new projects are placed.
 */
String defaultProjectsParent() {
  final home = Platform.environment['USERPROFILE'] ?? Directory.systemTemp.path;
  final docs = Directory(p.join(home, 'Documents'));
  final projects = Directory(p.join(docs.existsSync() ? docs.path : home, 'SimpleIDE Projects'));
  return projects.existsSync() ? projects.path : (docs.existsSync() ? docs.path : home);
}

/**
 * Picks an unused `untitled` folder name inside [parentDir].
 */
String suggestProjectName(String parentDir) {
  if (!Directory(p.join(parentDir, 'untitled')).existsSync()) return 'untitled';
  for (var i = 1; i < 1000; i++) {
    final candidate = 'untitled$i';
    if (!Directory(p.join(parentDir, candidate)).existsSync()) return candidate;
  }
  return 'untitled';
}

/**
 * Creates a new project folder, build configuration, and optional starter file.
 *
 * @param parentDir    directory that will contain the project folder
 * @param name         project folder name
 * @param template     language preset to initialize
 * @param createSample whether to write the template's starter file
 * @param buildTool    selected build system preset
 * @return the created project path and optional starter file path
 */
Future<({String projectDir, String? entryPath})> createProject({
  required String parentDir,
  required String name,
  required ProjectTemplate template,
  required bool createSample,
  String buildTool = 'Single file',
}) async {
  final dir = Directory(p.join(parentDir, name));
  await dir.create(recursive: true);

  final safePkg = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
  final pkgName = safePkg.isEmpty || RegExp(r'^\d').hasMatch(safePkg) ? 'app_$safePkg' : safePkg;

  String relEntry = template.entryFile ?? '';
  final extraFiles = <String, String>{};

  switch (buildTool) {
    case 'CMake':
      extraFiles['CMakeLists.txt'] = 'cmake_minimum_required(VERSION 3.16)\n'
          'project($pkgName)\n\n'
          '${template.id == 'cpp' ? 'set(CMAKE_CXX_STANDARD 17)\n' : 'set(CMAKE_C_STANDARD 11)\n'}'
          'add_executable($pkgName ${template.entryFile})\n';
    case 'Makefile':
      final cc = template.id == 'cpp' ? 'g++ -std=c++17' : 'gcc';
      extraFiles['Makefile'] = 'all:\n\t$cc ${template.entryFile} -o $pkgName -Wall\n\n'
          'clean:\n\trm -f $pkgName $pkgName.exe\n';
    case 'Gradle':
      relEntry = p.join('src', 'main', 'java', 'Main.java');
      extraFiles['settings.gradle.kts'] = 'rootProject.name = "$name"\n';
      extraFiles['build.gradle.kts'] = 'plugins {\n    application\n}\n\n'
          'application {\n    mainClass.set("Main")\n}\n';
    case 'Maven':
      relEntry = p.join('src', 'main', 'java', 'Main.java');
      extraFiles['pom.xml'] = '<project xmlns="http://maven.apache.org/POM/4.0.0">\n'
          '  <modelVersion>4.0.0</modelVersion>\n'
          '  <groupId>com.example</groupId>\n'
          '  <artifactId>$pkgName</artifactId>\n'
          '  <version>1.0.0</version>\n'
          '  <properties>\n'
          '    <maven.compiler.source>17</maven.compiler.source>\n'
          '    <maven.compiler.target>17</maven.compiler.target>\n'
          '  </properties>\n'
          '</project>\n';
    case 'Cargo':
      relEntry = p.join('src', 'main.rs');
      extraFiles['Cargo.toml'] = '[package]\n'
          'name = "$pkgName"\n'
          'version = "0.1.0"\n'
          'edition = "2021"\n';
    case 'Go Module':
      extraFiles['go.mod'] = 'module $pkgName\n\ngo 1.21\n';
    case 'Dart Package':
      relEntry = p.join('bin', 'main.dart');
      extraFiles['pubspec.yaml'] = 'name: $pkgName\n'
          'version: 0.1.0\n\n'
          'environment:\n'
          '  sdk: ^3.0.0\n';
    case 'npm':
      extraFiles['package.json'] = '{\n'
          '  "name": "$pkgName",\n'
          '  "version": "1.0.0",\n'
          '  "scripts": {\n'
          '    "start": "node index.js"\n'
          '  }\n'
          '}\n';
  }

  for (final e in extraFiles.entries) {
    final f = File(p.join(dir.path, e.key));
    if (!f.existsSync()) {
      await f.create(recursive: true);
      await f.writeAsString(e.value);
    }
  }

  String? entryPath;
  if (createSample && relEntry.isNotEmpty) {
    final file = File(p.join(dir.path, relEntry));
    if (!file.existsSync()) {
      await file.create(recursive: true);
      await file.writeAsString(template.starterCode);
    }
    entryPath = file.path;
  }
  return (projectDir: dir.path, entryPath: entryPath);
}
