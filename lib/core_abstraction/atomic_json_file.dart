import 'dart:io';

/// Write beside the target and rename only after a complete, flushed write.
/// A crash or a full disk must not truncate the user's only profile/settings.
void writeJsonFileAtomically(File target, String json) {
  target.parent.createSync(recursive: true);
  final staging = target.parent.createTempSync('.json-write-');
  final temporary = File('${staging.path}${Platform.pathSeparator}data.json');
  try {
    temporary.writeAsStringSync(json, flush: true);
    temporary.renameSync(target.path);
  } finally {
    try {
      if (temporary.existsSync()) temporary.deleteSync();
      // Never recursively delete a directory containing unrelated user files.
      staging.deleteSync();
    } catch (_) {
      // Do not obscure the write/rename error or invalidate a successful write.
    }
  }
}
