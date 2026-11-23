import 'package:flutter_test/flutter_test.dart';
import 'package:flux/core_abstraction/app_settings.dart';
import 'package:flux/core_abstraction/tun_application_routing.dart';

void main() {
  test(
    'old settings retain their defaults and appearance with routing disabled',
    () {
      final restored = AppSettings.fromJson({
        'homeBackground': 'colorBends',
        'language': 'en',
      });
      expect(restored.tunApplicationRouting.enabled, false);
      expect(restored.homeBackground, HomeBackground.colorBends);
      expect(restored.language, AppLanguage.en);
      expect(restored.onboardingCompleted, true);
    },
  );

  test('all three actions, mode, paths and disabled selections round-trip', () {
    final policy = TunApplicationRouting.fromJson({
      'enabled': true,
      'mode': 'whitelist',
      'rules': [
        {'processName': 'Chrome.exe', 'action': 'proxy'},
        {'processName': 'offline.exe', 'action': 'direct', 'enabled': false},
        {'processPath': r'D:\Apps\not-started.exe', 'action': 'block'},
      ],
    });
    final settings = const AppSettings().copyWith(
      tunApplicationRouting: policy,
      language: AppLanguage.ru,
    );
    expect(
      AppSettings.fromJson(settings.toJson()).tunApplicationRouting,
      policy,
    );
    expect(policy.defaultAction, TunApplicationAction.direct);
    expect(policy.suggestedAction, TunApplicationAction.proxy);
    expect(
      policy.copyWith(mode: TunApplicationRoutingMode.blacklist).defaultAction,
      TunApplicationAction.proxy,
    );
    expect(
      policy
          .copyWith(mode: TunApplicationRoutingMode.blacklist)
          .suggestedAction,
      TunApplicationAction.direct,
    );
    expect(
      settings
          .copyWith(homeBackground: HomeBackground.globe)
          .tunApplicationRouting,
      policy,
    );
  });

  for (final bad in [
    {'processName': '*.exe', 'action': 'proxy'},
    {'processName': 'x.exe', 'processPath': r'D:\x.exe', 'action': 'proxy'},
    {'processName': 'x.exe', 'action': 'anything'},
    {'processName': 'x.exe', 'action': 'proxy', 'enabled': 'true'},
    {'processName': 'x.exe', 'action': 'proxy', 'processId': 123},
    {'processName': r'D:\Apps\x.exe', 'action': 'proxy'},
    {'processPath': 'relative/x.exe', 'action': 'direct'},
    {'processPath': r'D:\Apps\..\x.exe', 'action': 'block'},
    {'processPath': r'\\server\x.exe', 'action': 'block'},
    {'processPath': r'D:\Apps\\x.exe', 'action': 'block'},
    {'processPath': r'D:\Apps.\x.exe', 'action': 'block'},
    {'processPath': r'D:\Apps \x.exe', 'action': 'block'},
    {'processPath': r'D:\Apps\x.exe:payload.exe', 'action': 'block'},
    {'processPath': r'\\.\device\x.exe', 'action': 'block'},
    {'processName': 'not-an-exe.dll', 'action': 'block'},
    {'processName': 'x\n.exe', 'action': 'block'},
  ]) {
    test('rejects malformed application rule $bad', () {
      expect(() => TunApplicationRule.fromJson(bad), throwsFormatException);
    });
  }

  test(
    'rejects duplicate identities case-insensitively without requiring files',
    () {
      expect(
        () => TunApplicationRouting.fromJson({
          'rules': [
            {'processName': 'x.exe', 'action': 'proxy'},
            {'processName': 'X.EXE', 'action': 'block'},
          ],
        }),
        throwsFormatException,
      );
      final path = TunApplicationRule.fromJson({
        'processPath': 'D:/No Such Folder/never.exe',
        'action': 'direct',
      });
      expect(path.value, r'D:\No Such Folder\never.exe');
    },
  );

  test(
    'invalid hand-edit is preserved, unrelated settings load, TUN refuses it',
    () {
      final raw = {
        'enabled': true,
        'mode': 'whitelist',
        'rules': [
          {'processName': 'x.exe', 'action': 'typo'},
        ],
      };
      final restored = AppSettings.fromJson({
        'language': 'en',
        'homeBackground': 'none',
        'tunApplicationRouting': raw,
      });
      expect(restored.language, AppLanguage.en);
      expect(restored.homeBackground, HomeBackground.none);
      expect(restored.tunApplicationRouting.validationError, isNotNull);
      expect(
        () => restored.tunApplicationRouting.requireValid(),
        throwsFormatException,
      );
      expect(
        restored
            .copyWith(pingAllOnStartup: true)
            .toJson()['tunApplicationRouting'],
        raw,
      );
    },
  );

  test(
    'oversized lists and unknown top-level keys are not silently accepted',
    () {
      expect(
        () => TunApplicationRouting.fromJson({'enabled': 'true'}),
        throwsFormatException,
      );
      expect(
        () => TunApplicationRouting.fromJson({'mode': 'allowlist'}),
        throwsFormatException,
      );
      expect(
        () => TunApplicationRouting.fromJson({'processId': 1}),
        throwsFormatException,
      );
      expect(
        () => TunApplicationRouting.fromJson({'rules': List.filled(513, {})}),
        throwsFormatException,
      );
    },
  );

  test(
    'absolute drive and UNC identities keep unicode and literal regex punctuation',
    () {
      for (final path in [
        r'D:\Игры\Game[1]+(x).exe',
        r'\\server.invalid\share\Player.exe',
        r'D:\app.exe',
      ]) {
        final rule = TunApplicationRule.fromJson({
          'processPath': path,
          'action': 'proxy',
        });
        expect(rule.value, path);
        expect(TunApplicationRule.fromJson(rule.toJson()), rule);
      }
    },
  );
}
