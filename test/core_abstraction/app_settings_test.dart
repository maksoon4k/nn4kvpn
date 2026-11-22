import 'package:flutter_test/flutter_test.dart';
import 'package:flux/core_abstraction/app_settings.dart';
import 'package:flux/core_abstraction/connection_session.dart';

void main() {
  group('First-run onboarding compatibility', () {
    test('a fresh installation keeps onboarding and the original background', () {
      const settings = AppSettings();
      expect(settings.onboardingCompleted, isFalse);
      expect(settings.homeBackground, HomeBackground.galaxy);
    });

    test('legacy settings do not unexpectedly restart onboarding on upgrade', () {
      expect(AppSettings.fromJson({}).onboardingCompleted, isTrue);
    });

    test('both explicit onboarding states survive persistence', () {
      for (final completed in [false, true]) {
        final settings = AppSettings(onboardingCompleted: completed);
        expect(
          AppSettings.fromJson(settings.toJson()).onboardingCompleted,
          completed,
        );
      }
    });
  });

  group('GitHub update settings', () {
    test('older settings get safe, backward-compatible defaults', () {
      final settings = AppSettings.fromJson({});
      expect(settings.updateRepository, defaultUpdateRepository);
      expect(settings.checkForUpdatesOnStartup, true);
      expect(settings.autoInstallUpdates, false);
    });

    test('round-trips configuration, but has no token field', () {
      final settings = const AppSettings().copyWith(
        updateRepository: 'owner/nn4k',
        checkForUpdatesOnStartup: false,
        autoInstallUpdates: true,
      );
      final json = settings.toJson();
      final restored = AppSettings.fromJson(json);
      expect(restored.updateRepository, 'owner/nn4k');
      expect(restored.checkForUpdatesOnStartup, false);
      expect(restored.autoInstallUpdates, true);
      expect(
        json.keys.any((key) => key.toLowerCase().contains('token')),
        false,
      );
    });
  });
  group('AppSettings.fromJson — autoStartPrivilege back-compat (трек 24)', () {
    test('migrates legacy autoStartOnBoot: true to standard', () {
      final settings = AppSettings.fromJson({'autoStartOnBoot': true});
      expect(settings.autoStartPrivilege, AppAutoStartPrivilege.standard);
    });

    test('migrates legacy autoStartOnBoot: false to none', () {
      final settings = AppSettings.fromJson({'autoStartOnBoot': false});
      expect(settings.autoStartPrivilege, AppAutoStartPrivilege.none);
    });

    test('defaults to none when neither field is present', () {
      final settings = AppSettings.fromJson({});
      expect(settings.autoStartPrivilege, AppAutoStartPrivilege.none);
    });

    test('prefers the new field over the legacy one once present', () {
      final settings = AppSettings.fromJson({
        'autoStartOnBoot': true,
        'autoStartPrivilege': 'elevated',
      });
      expect(settings.autoStartPrivilege, AppAutoStartPrivilege.elevated);
    });
  });

  test(
    'AppSettings round-trips new autostart/autoconnect fields through JSON',
    () {
      const settings = AppSettings(
        autoStartPrivilege: AppAutoStartPrivilege.elevated,
        autoStartShowWindow: true,
        autoConnectOnStartup: true,
        autoConnectMode: ConnectionMode.tun,
      );

      final restored = AppSettings.fromJson(settings.toJson());

      expect(restored.autoStartPrivilege, AppAutoStartPrivilege.elevated);
      expect(restored.autoStartShowWindow, isTrue);
      expect(restored.autoConnectOnStartup, isTrue);
      expect(restored.autoConnectMode, ConnectionMode.tun);
    },
  );

  test(
    'AppSettings.copyWith updates autostart/autoconnect fields independently',
    () {
      const settings = AppSettings();
      final updated = settings.copyWith(
        autoStartPrivilege: AppAutoStartPrivilege.standard,
        autoConnectOnStartup: true,
      );

      expect(updated.autoStartPrivilege, AppAutoStartPrivilege.standard);
      expect(updated.autoConnectOnStartup, isTrue);
      // Непереданные поля не трогаются.
      expect(updated.autoStartShowWindow, isFalse);
      expect(updated.autoConnectMode, ConnectionMode.proxy);
    },
  );

  group('showNotifications (трек 25)', () {
    test('defaults to true', () {
      const settings = AppSettings();
      expect(settings.showNotifications, isTrue);
    });

    test('round-trips false through JSON', () {
      const settings = AppSettings(showNotifications: false);
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.showNotifications, isFalse);
    });

    test(
      'missing key defaults to true (back-compat for existing settings.json)',
      () {
        final settings = AppSettings.fromJson({});
        expect(settings.showNotifications, isTrue);
      },
    );
  });
}
