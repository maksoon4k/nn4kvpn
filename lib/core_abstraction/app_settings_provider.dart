import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_settings.dart';
import 'app_settings_storage.dart';

final appSettingsStorageProvider = Provider<AppSettingsStorage>(
  (_) => appSettingsStorage,
);

final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );

class AppSettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(appSettingsStorageProvider).load();

  void update(AppSettings Function(AppSettings settings) transform) {
    final next = transform(state);
    ref.read(appSettingsStorageProvider).save(next);
    state = next;
  }
}
