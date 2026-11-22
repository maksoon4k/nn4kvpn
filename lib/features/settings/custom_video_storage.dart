import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'managed_background_storage.dart';

/// Копия видеофайла, выбранного юзером под `HomeBackground.customVideo`
/// (`AppSettings.customVideoPath`) — кроссплатформенно, через
/// `path_provider`, а не `app_paths.dart` (тот хардкодит %APPDATA%, работает
/// только на Windows). Храним копию, а не оригинальный путь: юзер мог
/// выбрать файл со съёмного диска/временной папки, который может исчезнуть
/// или к которому на Android нет постоянного доступа без copy.
Future<String> importCustomVideo(String sourcePath) async {
  final supportDir = await getApplicationSupportDirectory();
  final videoDir = Directory('${supportDir.path}/backgrounds');
  return ManagedBackgroundStorage(
    videoDir,
    prefix: 'custom_video',
  ).import(sourcePath);
}

/// Убирает сохранённую копию — вызывается, когда юзер снимает видеофон.
Future<void> deleteCustomVideo(String path) async {
  final supportDir = await getApplicationSupportDirectory();
  await ManagedBackgroundStorage(
    Directory('${supportDir.path}/backgrounds'),
    prefix: 'custom_video',
  ).delete(path);
}
