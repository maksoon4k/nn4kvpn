import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/core_abstraction/app_settings.dart';
import 'package:flux/core_abstraction/app_settings_provider.dart';
import 'package:flux/core_abstraction/app_settings_storage.dart';
import 'package:flux/core_abstraction/tun_application_routing.dart';

void main() {
  test(
    'actual isolated settings.json retains application rules across restart and unrelated changes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nn4k-app-routing-persistence-test-',
      );
      final file = File('${directory.path}/settings.json');
      final storage = AppSettingsStorage(file: file);
      final policy = TunApplicationRouting.fromJson({
        'enabled': true,
        'mode': 'whitelist',
        'rules': [
          {'processName': 'Browser.exe', 'action': 'proxy'},
          {'processPath': r'D:\NotInstalled\player.exe', 'action': 'direct'},
          {'processName': 'Blocked.exe', 'action': 'block', 'enabled': false},
        ],
      });
      storage.save(
        const AppSettings(
          language: AppLanguage.en,
          homeBackground: HomeBackground.galaxy,
          tunDnsServer: '9.9.9.9',
          tunDnsSecondaryServer: '149.112.112.112',
          onboardingCompleted: true,
        ),
      );
      final first = ProviderContainer(
        overrides: [appSettingsStorageProvider.overrideWithValue(storage)],
      );
      try {
        first
            .read(appSettingsProvider.notifier)
            .update(
              (settings) => settings.copyWith(tunApplicationRouting: policy),
            );
        first
            .read(appSettingsProvider.notifier)
            .update((settings) => settings.copyWith(pingAllOnStartup: true));
        expect(
          jsonDecode(await file.readAsString())['tunApplicationRouting'],
          policy.toJson(),
        );
        final restarted = ProviderContainer(
          overrides: [appSettingsStorageProvider.overrideWithValue(storage)],
        );
        try {
          final loaded = restarted.read(appSettingsProvider);
          expect(loaded.tunApplicationRouting, policy);
          expect(loaded.pingAllOnStartup, true);
          expect(loaded.language, AppLanguage.en);
          expect(loaded.homeBackground, HomeBackground.galaxy);
          expect(loaded.tunDnsServer, '9.9.9.9');
          expect(loaded.tunDnsSecondaryServer, '149.112.112.112');
          expect(loaded.onboardingCompleted, true);
          restarted
              .read(appSettingsProvider.notifier)
              .update(
                (settings) => settings.copyWith(
                  tunApplicationRouting: settings.tunApplicationRouting
                      .copyWith(
                        rules: [
                          settings.tunApplicationRouting.rules.first.copyWith(
                            enabled: false,
                          ),
                          ...settings.tunApplicationRouting.rules.skip(1),
                        ],
                      ),
                ),
              );
          expect(
            storage.load().tunApplicationRouting.rules.first.enabled,
            false,
          );
          expect(storage.load().tunApplicationRouting.rules.length, 3);
        } finally {
          restarted.dispose();
        }
      } finally {
        first.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'invalid hand-edited section is not discarded by saving another setting',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nn4k-app-routing-handedit-test-',
      );
      final file = File('${directory.path}/settings.json');
      final broken = {
        'enabled': true,
        'mode': 'whitelist',
        'rules': [
          {'processName': 'x.exe', 'action': 'typo'},
        ],
      };
      await file.writeAsString(
        jsonEncode({
          'language': 'en',
          'homeBackground': 'globe',
          'tunApplicationRouting': broken,
        }),
      );
      final storage = AppSettingsStorage(file: file);
      final container = ProviderContainer(
        overrides: [appSettingsStorageProvider.overrideWithValue(storage)],
      );
      try {
        expect(
          container
              .read(appSettingsProvider)
              .tunApplicationRouting
              .validationError,
          isNotNull,
        );
        container
            .read(appSettingsProvider.notifier)
            .update((settings) => settings.copyWith(pingAllOnStartup: true));
        expect(
          jsonDecode(await file.readAsString())['tunApplicationRouting'],
          broken,
        );
        expect(storage.load().language, AppLanguage.en);
        expect(storage.load().homeBackground, HomeBackground.globe);
      } finally {
        container.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
}
