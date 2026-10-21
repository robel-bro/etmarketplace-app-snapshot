import 'dart:io';

void main() {
  final dir = Directory('lib');
  if (!dir.existsSync()) {
    print('lib folder not found');
    return;
  }

  final staticStrings = <String>{};

  // Match t('...') – single‑quoted arguments
  final singleQuotePattern = RegExp(r"t\('(.*?)'\)");
  // Match t("...") – double‑quoted arguments
  final doubleQuotePattern = RegExp(r't\("(.*?)"\)');

  for (final file in dir.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart') || file.path.contains('translations.dart')) continue;

    final content = file.readAsStringSync();

    for (final pattern in [singleQuotePattern, doubleQuotePattern]) {
      for (final match in pattern.allMatches(content)) {
        final key = match.group(1)!;
        // Ignore strings that contain template expressions like $var or ${...}
        if (key.contains(r'$')) continue;
        staticStrings.add(key);
      }
    }
  }

  final sorted = staticStrings.toList()..sort();

  final buffer = StringBuffer();
  buffer.writeln('// AUTO‑GENERATED – static strings only');
  buffer.writeln('const Map<String, String> amTranslations = {');
  for (final key in sorted) {
    // Escape single quotes and backslashes
    final escapedKey = key.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final escapedVal = '[am] $key'.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    buffer.writeln("  '$escapedKey': '$escapedVal',");
  }
  buffer.writeln('};');

  File('lib/utils/translations.dart').writeAsStringSync(buffer.toString());
  print('Generated clean translations.dart with ${sorted.length} static keys.');
}