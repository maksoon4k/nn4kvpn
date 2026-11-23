import 'package:flutter_test/flutter_test.dart';
import 'package:flux/core_abstraction/app_settings.dart';
import 'package:flux/core_abstraction/connection_session.dart';

void main() {
  group('First-run onboarding compatibility', () {
    test(
      'a fresh installation keeps onboarding and the original background',
      () {
        const settings = AppSettings();
        expect(settings.onboardingCompleted, isFalse);
        expect(settings.homeBackground, HomeBackground.galaxy);
      },
    );

    test(
      'legacy settings do not unexpectedly restart onboarding on upgrade',
      () {
        expect(AppSettings.fromJson({}).onboardingCompleted, isTrue);
      },
    );

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

  group('Public update settings', () {
    test('older settings get safe, backward-compatible defaults', () {
      final settings = AppSettings.fromJson({});
      expect(defaultUpdateRepository, 'maksoon4k/nn4kvpn');
      expect(settings.toJson(), isNot(contains('updateRepository')));
      expect(settings.checkForUpdatesOnStartup, true);
      expect(settings.autoInstallUpdates, false);
    });

    test(
      'round-trips consent, but has no editable publisher or token field',
      () {
        final settings = const AppSettings().copyWith(
          checkForUpdatesOnStartup: false,
          autoInstallUpdates: true,
        );
        final json = settings.toJson();
        final restored = AppSettings.fromJson(json);
        expect(json['autoInstallUpdateOrigin'], defaultUpdateRepository);
        expect(json, isNot(contains('updateRepository')));
        expect(restored.checkForUpdatesOnStartup, false);
        expect(restored.autoInstallUpdates, true);
        expect(
          json.keys.any((key) => key.toLowerCase().contains('token')),
          false,
        );
      },
    );

    test(
      'ignores legacy publisher/token data and requires fresh publisher consent',
      () {
        final settings = AppSettings.fromJson({
          'updateRepository': 'other/nn4k',
          'updateToken': 'synthetic_legacy_credential',
          'autoInstallUpdates': true,
          'homeBackground': 'none',
        });
        expect(settings.autoInstallUpdates, false);
        expect(settings.homeBackground, HomeBackground.none);
        expect(settings.onboardingCompleted, true);
        expect(settings.toJson(), isNot(contains('updateRepository')));
        expect(settings.toJson(), isNot(contains('updateToken')));
      },
    );

    test(
      'preserves legacy consent only for the internally pinned publisher',
      () {
        expect(
          AppSettings.fromJson({
            'updateRepository': defaultUpdateRepository.toUpperCase(),
            'autoInstallUpdates': true,
          }).autoInstallUpdates,
          true,
        );
        for (final origin in ['', null, 123, 'other/nn4k']) {
          expect(
            AppSettings.fromJson({
              'autoInstallUpdateOrigin': origin,
              'autoInstallUpdates': true,
            }).autoInstallUpdates,
            false,
          );
        }
      },
    );
  });

  group('Persistent diagnostic DNS pair', () {
    test('legacy single DNS is preserved without inventing a backup', () {
      final settings = AppSettings.fromJson({'tunDnsServer': '1.1.1.1'});
      expect(settings.tunDnsServer, '1.1.1.1');
      expect(settings.tunDnsSecondaryServer, '');
    });

    test(
      'both measured addresses round-trip, including fastest-secondary-first',
      () {
        final settings = const AppSettings().copyWith(
          tunDnsServer: '77.88.8.1',
          tunDnsSecondaryServer: '77.88.8.8',
        );
        final restored = AppSettings.fromJson(settings.toJson());
        expect(restored.tunDnsServer, '77.88.8.1');
        expect(restored.tunDnsSecondaryServer, '77.88.8.8');
      },
    );

    test('a manual primary change clears a stale diagnostic backup', () {
      const settings = AppSettings(
        tunDnsServer: '1.1.1.1',
        tunDnsSecondaryServer: '1.0.0.1',
      );
      expect(
        settings.copyWith(tunDnsServer: '8.8.8.8').tunDnsSecondaryServer,
        '',
      );
      expect(
        settings.copyWith(language: AppLanguage.en).tunDnsSecondaryServer,
        '1.0.0.1',
      );
      expect(
        settings.copyWith(tunDnsSecondaryServer: '').toJson(),
        isNot(contains('tunDnsSecondaryServer')),
      );
    });

    test(
      'imported backup cannot be from a different provider or arbitrary host',
      () {
        for (final backup in [
          '8.8.8.8',
          '1.1.1.1',
          'resolver.invalid',
          7,
          null,
        ]) {
          final settings = AppSettings.fromJson({
            'tunDnsServer': '1.1.1.1',
            'tunDnsSecondaryServer': backup,
          });
          expect(settings.tunDnsServer, '1.1.1.1');
          expect(settings.tunDnsSecondaryServer, '');
        }
      },
    );
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
