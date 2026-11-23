import '../../core_abstraction/app_settings.dart';

typedef BackgroundSettingsUpdate =
    void Function(AppSettings Function(AppSettings) transform);

/// Import -> persist -> retire. A failed save or an obsolete picker must not
/// remove the background currently referenced by the saved configuration.
Future<bool> replaceCustomBackground({
  required HomeBackground kind,
  required String sourcePath,
  required Future<String> Function(String) import,
  required Future<void> Function(String) delete,
  required AppSettings Function() readSettings,
  required BackgroundSettingsUpdate updateSettings,
  required bool Function() canCommit,
}) async {
  assert(
    kind == HomeBackground.customImage || kind == HomeBackground.customVideo,
  );
  final expected = readSettings();
  final storedPath = await import(sourcePath);
  var committed = false;
  String? previousPath;
  try {
    if (!canCommit()) return false;
    final current = readSettings();
    if (current.homeBackground != expected.homeBackground ||
        current.customImagePath != expected.customImagePath ||
        current.customVideoPath != expected.customVideoPath) {
      return false;
    }
    updateSettings((settings) {
      previousPath = kind == HomeBackground.customImage
          ? settings.customImagePath
          : settings.customVideoPath;
      return kind == HomeBackground.customImage
          ? settings.copyWith(homeBackground: kind, customImagePath: storedPath)
          : settings.copyWith(
              homeBackground: kind,
              customVideoPath: storedPath,
            );
    });
    committed = true;
  } finally {
    if (!committed) await _retire(delete, storedPath);
  }
  if (previousPath != null && previousPath != storedPath) {
    await _retire(delete, previousPath!);
  }
  return true;
}

Future<void> clearCustomBackground({
  required HomeBackground kind,
  required BackgroundSettingsUpdate updateSettings,
  required Future<void> Function(String) delete,
}) async {
  String? previousPath;
  updateSettings((settings) {
    previousPath = kind == HomeBackground.customImage
        ? settings.customImagePath
        : settings.customVideoPath;
    final background = settings.homeBackground == kind
        ? HomeBackground.none
        : settings.homeBackground;
    return kind == HomeBackground.customImage
        ? settings.copyWith(
            homeBackground: background,
            clearCustomImagePath: true,
          )
        : settings.copyWith(
            homeBackground: background,
            clearCustomVideoPath: true,
          );
  });
  if (previousPath != null) await _retire(delete, previousPath!);
}

Future<void> _retire(Future<void> Function(String) delete, String path) async {
  try {
    await delete(path);
  } catch (_) {
    // A decoder may still have the retired copy open on Windows. Never turn
    // successful persistence into an apparent failure or remove another file.
  }
}
