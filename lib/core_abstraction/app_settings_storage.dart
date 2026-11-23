import 'dart:convert';
import 'dart:io';

import 'app_settings.dart';
import 'atomic_json_file.dart';

/// Хранилище настроек приложения — отдельный файл от профиля серверов
/// (`profile_storage.dart`), тот же каталог `%AppData%\flux`.
class AppSettingsStorage {
  final File? _overrideFile;
  const AppSettingsStorage({File? file}) : _overrideFile = file;

  File _file() {
    if (_overrideFile != null) return _overrideFile;
    final appData = Platform.environment['APPDATA'];
    final dir = appData != null
        ? '$appData\\flux'
        : '${Directory.systemTemp.path}\\flux';
    return File('$dir\\settings.json');
  }

  AppSettings load() {
    final file = _file();
    if (!file.existsSync()) return const AppSettings();
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return AppSettings.fromJson(json);
    } catch (_) {
      return const AppSettings();
    }
  }

  void save(AppSettings settings) {
    final file = _file();
    writeJsonFileAtomically(file, jsonEncode(settings.toJson()));
  }
}

const appSettingsStorage = AppSettingsStorage();
