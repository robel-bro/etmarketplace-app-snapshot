import 'dart:io';

void main() {
  final dir = Directory('lib');
  if (!dir.existsSync()) return;

  for (final file in dir.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    var content = file.readAsStringSync();
    var changed = false;

    // We'll look for SnackBar( ... ) blocks that contain 'margin:' but no 'behavior:'
    // A simple line-by-line approach: find lines with 'SnackBar(' and then check the following lines.
    // Better: use a regex that matches the whole SnackBar constructor and adds the missing line.
    // Pattern: SnackBar( ... margin: ... ) without behavior:
    final pattern = RegExp(
      r"(SnackBar\(\s*)"                // SnackBar(
      r"((?:[^()]|\((?:[^()]*\)))*?)"  // content (non-greedy, allows nested parens)
      r"(margin:\s*[^,)]+)"            // margin: something
      r"((?:[^()]|\((?:[^()]*\)))*?)"  // rest
      r"\)",                           // closing )
      multiLine: true,
    );

    content = content.replaceAllMapped(pattern, (match) {
      final beforeMargin = match.group(2)!;
      final margin = match.group(3)!;
      final afterMargin = match.group(4)!;
      // If there's already a behavior: line, leave it alone
      if (match.group(0)!.contains('behavior:')) {
        return match.group(0)!; // no change
      }
      // Insert behavior: SnackBarBehavior.floating, after the margin line
      return "SnackBar(\n$beforeMargin$margin,\nbehavior: SnackBarBehavior.floating,$afterMargin)";
    });

    if (content != file.readAsStringSync()) {
      file.writeAsStringSync(content);
      print('Fixed SnackBar in: ${file.path}');
      changed = true;
    }
  }

  print('All SnackBar issues fixed. Now rebuild.');
}