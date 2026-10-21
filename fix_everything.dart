import 'dart:io';

final neededImport = "import 'package:et_marketplace_app/utils/translations.dart';";

void main() {
  final dir = Directory('lib');
  if (!dir.existsSync()) {
    print('ERROR: lib folder not found');
    return;
  }

  // ---- Fix all Dart files (except translations.dart) ----
  for (final file in dir.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart') || file.path.contains('translations.dart')) {
      continue;
    }

    var content = file.readAsStringSync();
    var changed = false;

    // 1) Remove 'const' from any line that contains t('
    final lines = content.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].contains("t('") || lines[i].contains('t("')) {
        final trimmed = lines[i].trimLeft();
        if (trimmed.startsWith('const ')) {
          lines[i] = lines[i].replaceFirst('const ', '');
          changed = true;
        }
      }
    }
    content = lines.join('\n');

    // 2) Add import if file uses t( and import is missing
    if (content.contains("t('") || content.contains('t("')) {
      if (!content.contains(neededImport)) {
        final newLines = content.split('\n');
        int lastImport = -1;
        for (int i = 0; i < newLines.length; i++) {
          if (newLines[i].trimLeft().startsWith('import ')) {
            lastImport = i;
          }
        }
        if (lastImport >= 0) {
          newLines.insert(lastImport + 1, neededImport);
        } else {
          newLines.insert(0, neededImport);
        }
        content = newLines.join('\n');
        changed = true;
      }
    }

    if (changed) {
      file.writeAsStringSync(content);
      print('Fixed: ${file.path}');
    }
  }

  // ---- Generate a clean translations.dart ----
  final translationsContent = '''
// lib/utils/translations.dart
import '../core/app_config.dart';

const Map<String, String> amTranslations = {};

String t(String english) {
  if (AppConfig.isAmharic.value) {
    return amTranslations[english] ?? english;
  }
  return english;
}
''';
  File('lib/utils/translations.dart').writeAsStringSync(translationsContent);
  print('Created clean translations.dart');

  print('All done! Now run: flutter clean && flutter pub get && flutter run');
}