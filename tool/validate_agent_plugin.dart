// Validates the agent plugin distribution tree (Claude Code + Codex).
//
// Run from the repository root:
//
//     dart tool/validate_agent_plugin.dart
//
// Checks, without any network access or AI involvement:
//   - `.claude-plugin/marketplace.json` and the plugin manifest parse, use
//     kebab-case names, and reference plugin directories that exist.
//   - The pubspec version, plugin manifest version, and marketplace entry
//     version are identical (no version drift between package and plugin).
//   - Every skill directory contains a `SKILL.md` whose frontmatter parses,
//     has `name` matching the directory and a `description` within limits.
//   - Relative links inside the plugin tree resolve to files that exist and
//     never escape the plugin root (the installed plugin is self-contained).
//   - No absolute filesystem paths leak into distributed plugin files.
//   - `.pubignore` keeps the plugin tree out of the pub.dev archive, so the
//     archive can never contain a partial plugin.
import 'dart:convert';
import 'dart:io';

final List<String> _errors = <String>[];
final List<String> _warnings = <String>[];

void fail(String message) => _errors.add(message);

void warn(String message) => _warnings.add(message);

void main() {
  final repoRoot = _findRepoRoot();
  final marketplace = _checkMarketplace(repoRoot);
  if (marketplace != null) {
    _checkPlugins(repoRoot, marketplace);
  }
  _checkCodexMarketplace(repoRoot);
  _checkPubignore(repoRoot);

  for (final warning in _warnings) {
    stdout.writeln('WARN: $warning');
  }
  if (_errors.isEmpty) {
    stdout.writeln('Agent plugin validation passed.');
    return;
  }
  for (final error in _errors) {
    stderr.writeln('ERROR: $error');
  }
  exitCode = 1;
}

Directory _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      stderr.writeln('ERROR: could not find pubspec.yaml; run from the repo.');
      exit(1);
    }
    dir = parent;
  }
}

final RegExp _kebabCase = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

Map<String, Object?>? _readJson(File file) {
  if (!file.existsSync()) {
    fail('Missing required file: ${file.path}');
    return null;
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map<String, Object?>) return decoded;
    fail('${file.path}: top-level JSON value must be an object.');
  } on FormatException catch (e) {
    fail('${file.path}: invalid JSON (${e.message}).');
  }
  return null;
}

Map<String, Object?>? _checkMarketplace(Directory repoRoot) {
  final file = File('${repoRoot.path}/.claude-plugin/marketplace.json');
  final marketplace = _readJson(file);
  if (marketplace == null) return null;

  final name = marketplace['name'];
  if (name is! String || !_kebabCase.hasMatch(name)) {
    fail('marketplace.json: "name" must be a kebab-case string, got $name.');
  }
  final owner = marketplace['owner'];
  if (owner is! Map || owner['name'] is! String) {
    fail('marketplace.json: "owner.name" is required.');
  }
  final plugins = marketplace['plugins'];
  if (plugins is! List || plugins.isEmpty) {
    fail('marketplace.json: "plugins" must be a non-empty array.');
    return null;
  }
  final seen = <String>{};
  for (final entry in plugins) {
    if (entry is! Map) {
      fail('marketplace.json: every plugin entry must be an object.');
      continue;
    }
    final pluginName = entry['name'];
    if (pluginName is! String || !_kebabCase.hasMatch(pluginName)) {
      fail('marketplace.json: plugin "name" must be kebab-case: $pluginName.');
    } else if (!seen.add(pluginName)) {
      fail('marketplace.json: duplicate plugin name "$pluginName".');
    }
  }
  return marketplace;
}

void _checkPlugins(Directory repoRoot, Map<String, Object?> marketplace) {
  final pubspecVersion = _pubspecVersion(repoRoot);
  final entries = (marketplace['plugins']! as List)
      .whereType<Map<String, Object?>>();
  for (final entry in entries) {
    final source = entry['source'];
    if (source is! String || !source.startsWith('./')) {
      fail('marketplace.json: plugin "source" must be a relative "./" path.');
      continue;
    }
    final pluginRoot = Directory('${repoRoot.path}/${source.substring(2)}');
    if (!pluginRoot.existsSync()) {
      fail('marketplace.json: source "$source" does not exist.');
      continue;
    }
    final manifest = _readJson(
      File('${pluginRoot.path}/.claude-plugin/plugin.json'),
    );
    if (manifest == null) continue;
    final codexManifest = _readJson(
      File('${pluginRoot.path}/.codex-plugin/plugin.json'),
    );

    if (manifest['name'] != entry['name']) {
      fail(
        '${pluginRoot.path}: plugin.json name "${manifest['name']}" does '
        'not match marketplace entry "${entry['name']}".',
      );
    }
    if (codexManifest != null && codexManifest['name'] != entry['name']) {
      fail(
        '${pluginRoot.path}: .codex-plugin name "${codexManifest['name']}" '
        'does not match marketplace entry "${entry['name']}".',
      );
    }
    final versions = <String, Object?>{
      'pubspec.yaml': pubspecVersion,
      '.claude-plugin/plugin.json': manifest['version'],
      '.codex-plugin/plugin.json': codexManifest?['version'],
      'marketplace entry': entry['version'],
    };
    if (versions.values.toSet().length != 1) {
      fail('Version drift: $versions must all be identical.');
    }
    _checkSkills(pluginRoot);
    _checkPluginFiles(pluginRoot);
  }
}

String? _pubspecVersion(Directory repoRoot) {
  final pubspec = File('${repoRoot.path}/pubspec.yaml');
  for (final line in pubspec.readAsLinesSync()) {
    final match = RegExp(r'^version:\s*(\S+)\s*$').firstMatch(line);
    if (match != null) return match.group(1);
  }
  fail('pubspec.yaml: no version found.');
  return null;
}

void _checkSkills(Directory pluginRoot) {
  final skillsDir = Directory('${pluginRoot.path}/skills');
  if (!skillsDir.existsSync()) {
    fail('${pluginRoot.path}: missing skills/ directory.');
    return;
  }
  final skillDirs = skillsDir.listSync().whereType<Directory>().toList();
  if (skillDirs.isEmpty) {
    fail('${skillsDir.path}: contains no skill directories.');
  }
  for (final dir in skillDirs) {
    final dirName = dir.uri.pathSegments.lastWhere(
      (segment) => segment.isNotEmpty,
    );
    final skillFile = File('${dir.path}/SKILL.md');
    if (!skillFile.existsSync()) {
      fail('${dir.path}: missing SKILL.md.');
      continue;
    }
    final frontmatter = _parseFrontmatter(skillFile);
    if (frontmatter == null) continue;
    final name = frontmatter['name'];
    if (name == null || !_kebabCase.hasMatch(name)) {
      fail('${skillFile.path}: frontmatter "name" must be kebab-case.');
    } else if (name != dirName) {
      fail('${skillFile.path}: name "$name" must match directory "$dirName".');
    }
    final description = frontmatter['description'];
    if (description == null || description.trim().isEmpty) {
      fail('${skillFile.path}: frontmatter "description" is required.');
    } else if (description.length > 1024) {
      fail(
        '${skillFile.path}: description exceeds 1024 characters '
        '(${description.length}).',
      );
    }
  }
}

/// Parses the strict frontmatter subset used by this repository: a `---`
/// fence, single-line `key: value` pairs, and a closing `---`. Keeping the
/// format this simple is deliberate; it stays portable across agent clients.
Map<String, String>? _parseFrontmatter(File skillFile) {
  final lines = skillFile.readAsLinesSync();
  if (lines.isEmpty || lines.first.trim() != '---') {
    fail('${skillFile.path}: must start with a `---` frontmatter fence.');
    return null;
  }
  final result = <String, String>{};
  for (final line in lines.skip(1)) {
    if (line.trim() == '---') return result;
    if (line.trim().isEmpty) continue;
    final match = RegExp(
      r'^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$',
    ).firstMatch(line);
    if (match == null) {
      fail(
        '${skillFile.path}: frontmatter line is not a single-line '
        '"key: value" pair: "$line".',
      );
      return null;
    }
    var value = match.group(2)!.trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    result[match.group(1)!] = value;
  }
  fail('${skillFile.path}: frontmatter fence `---` is never closed.');
  return null;
}

final RegExp _markdownLink = RegExp(r'\]\(([^)#][^)]*)\)');
final RegExp _absolutePath = RegExp(
  r'(/Users/|/home/|[A-Za-z]:\\\\|/private/tmp/)',
);

void _checkPluginFiles(Directory pluginRoot) {
  final rootPath = pluginRoot.resolveSymbolicLinksSync();
  final files = pluginRoot
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (file) =>
            file.path.endsWith('.md') ||
            file.path.endsWith('.json') ||
            file.path.endsWith('.yaml') ||
            file.path.endsWith('.dart'),
      );
  for (final file in files) {
    final content = file.readAsStringSync();
    if (_absolutePath.hasMatch(content)) {
      fail('${file.path}: contains an absolute filesystem path.');
    }
    if (!file.path.endsWith('.md')) continue;
    for (final match in _markdownLink.allMatches(content)) {
      final target = match.group(1)!.trim();
      if (target.startsWith('http://') ||
          target.startsWith('https://') ||
          target.startsWith('mailto:') ||
          target.contains('://')) {
        continue;
      }
      final resolved = File.fromUri(
        file.parent.uri.resolve(target.split('#').first),
      );
      if (!resolved.existsSync()) {
        fail('${file.path}: link target "$target" does not exist.');
        continue;
      }
      if (!resolved.resolveSymbolicLinksSync().startsWith(rootPath)) {
        fail(
          '${file.path}: link "$target" escapes the plugin root; the '
          'installed plugin must be self-contained.',
        );
      }
    }
  }
}

void _checkCodexMarketplace(Directory repoRoot) {
  final file = File('${repoRoot.path}/.agents/plugins/marketplace.json');
  final marketplace = _readJson(file);
  if (marketplace == null) return;
  final name = marketplace['name'];
  if (name is! String || !_kebabCase.hasMatch(name)) {
    fail('${file.path}: "name" must be a kebab-case string, got $name.');
  }
  final plugins = marketplace['plugins'];
  if (plugins is! List || plugins.isEmpty) {
    fail('${file.path}: "plugins" must be a non-empty array.');
    return;
  }
  for (final entry in plugins.whereType<Map<String, Object?>>()) {
    final source = entry['source'];
    if (source is! Map ||
        source['source'] != 'local' ||
        source['path'] is! String ||
        !(source['path'] as String).startsWith('./')) {
      fail(
        '${file.path}: plugin "source" must be '
        '{"source": "local", "path": "./..."} for a repo marketplace.',
      );
      continue;
    }
    final path = (source['path'] as String).substring(2);
    final pluginRoot = Directory('${repoRoot.path}/$path');
    if (!pluginRoot.existsSync()) {
      fail('${file.path}: source path "$path" does not exist.');
      continue;
    }
    if (!File('${pluginRoot.path}/.codex-plugin/plugin.json').existsSync()) {
      fail(
        '${pluginRoot.path}: missing .codex-plugin/plugin.json required '
        'by the Codex marketplace entry.',
      );
    }
  }
}

void _checkPubignore(Directory repoRoot) {
  final pubignore = File('${repoRoot.path}/.pubignore');
  if (!pubignore.existsSync()) {
    fail(
      '.pubignore is missing; the pub.dev archive would ship a partial '
      'plugin tree (hidden manifests are always excluded by pub).',
    );
    return;
  }
  final lines = pubignore
      .readAsLinesSync()
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toList();
  if (!lines.any((line) => line == 'agent_plugin/' || line == 'agent_plugin')) {
    fail(
      '.pubignore must exclude agent_plugin/ so pub.dev never ships '
      'skills without their hidden manifests.',
    );
  }
  if (!lines.any((line) => line == 'tool/' || line == 'tool')) {
    warn(
      '.pubignore does not exclude tool/; the validation script would be '
      'published to pub.dev.',
    );
  }
}
