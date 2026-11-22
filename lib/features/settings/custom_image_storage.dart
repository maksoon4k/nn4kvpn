import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'managed_background_storage.dart';

/// Стабильная локальная копия картинки-фона. Оригинал можно удалить или
/// выбрать с внешнего носителя — фон приложения от этого не пропадёт.
Future<String> importCustomImage(String sourcePath) async {
  final supportDir = await getApplicationSupportDirectory();
  final imageDir = Directory('${supportDir.path}/background-images');
  return ManagedBackgroundStorage(
    imageDir,
    prefix: 'custom_background',
  ).import(sourcePath);
}

Future<void> deleteCustomImage(String path) async {
  final supportDir = await getApplicationSupportDirectory();
  await ManagedBackgroundStorage(
    Directory('${supportDir.path}/background-images'),
    prefix: 'custom_background',
  ).delete(path);
}
