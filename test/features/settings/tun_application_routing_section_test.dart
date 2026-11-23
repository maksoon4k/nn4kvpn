import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/core_abstraction/app_settings.dart';
import 'package:flux/core_abstraction/app_settings_provider.dart';
import 'package:flux/core_abstraction/app_settings_storage.dart';
import 'package:flux/core_abstraction/tun_application_routing.dart';
import 'package:flux/features/settings/tun_application_routing_section.dart';
import 'package:flux/features/settings/windows_process_catalog.dart';
import 'package:flux/widgets/port_ui/port_ui.dart';

import '../../support/tool_host.dart';

class FixtureSettingsStorage extends AppSettingsStorage {
  AppSettings current;
  final saved = <AppSettings>[];
  bool failSave = false;
  FixtureSettingsStorage([this.current = const AppSettings()]);
  @override
  AppSettings load() => current;
  @override
  void save(AppSettings settings) {
    if (failSave) throw const FileSystemException('Fixture disk failure');
    current = settings;
    saved.add(settings);
  }
}

class FixtureProcessCatalog implements ApplicationProcessSource {
  List<RunningApplication> applications = const [
    RunningApplication(
      name: 'Browser.exe',
      paths: [r'D:\Apps\Browser.exe'],
      processCount: 3,
    ),
    RunningApplication(
      name: 'Player.exe',
      paths: [r'D:\Player\Player.exe'],
      processCount: 1,
    ),
  ];
  Future<List<RunningApplication>>? hold;
  Object? error;
  int calls = 0;
  @override
  Future<List<RunningApplication>> list() async {
    calls++;
    if (error != null) throw error!;
    return await hold ?? applications;
  }
}

void main() {
  late FixtureSettingsStorage storage;
  late FixtureProcessCatalog catalog;
  late ProviderContainer container;
  setUp(() {
    storage = FixtureSettingsStorage(
      const AppSettings(
        language: AppLanguage.en,
        homeBackground: HomeBackground.globe,
      ),
    );
    catalog = FixtureProcessCatalog();
    container = ProviderContainer(
      overrides: [
        appSettingsStorageProvider.overrideWithValue(storage),
        applicationProcessSourceProvider.overrideWithValue(catalog),
      ],
    );
  });
  tearDown(() => container.dispose());
  TunApplicationRouting policy() =>
      container.read(appSettingsProvider).tunApplicationRouting;
  Future<void> showSection(WidgetTester tester) => tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: toolHost(const TunApplicationRoutingSection(), width: 560),
    ),
  );

  testWidgets(
    'enable, fallback mode and manually added absent applications persist without changing appearance',
    (tester) async {
      await showSection(tester);
      tester
          .widget<PortSwitch>(
            find.byKey(const ValueKey('tun-app-routing-enabled')),
          )
          .onChanged!(true);
      await tester.pump();
      tester
          .widget<PortSelect<TunApplicationRoutingMode>>(
            find.byKey(const ValueKey('tun-app-mode-blacklist')),
          )
          .onChanged(TunApplicationRoutingMode.whitelist);
      await tester.pump();
      await tapToolKey(tester, 'tun-app-add');
      await tester.enterText(
        find.byKey(const ValueKey('tun-app-target')),
        'NotStarted.exe',
      );
      await tapToolKey(tester, 'tun-app-rule-save');
      expect(policy().enabled, true);
      expect(policy().mode, TunApplicationRoutingMode.whitelist);
      expect(policy().rules.single.value, 'NotStarted.exe');
      expect(policy().rules.single.action, TunApplicationAction.proxy);
      expect(catalog.calls, 0);
      expect(storage.current.language, AppLanguage.en);
      expect(storage.current.homeBackground, HomeBackground.globe);
      await tester.pumpWidget(const SizedBox.shrink());
      final restarted = ProviderContainer(
        overrides: [appSettingsStorageProvider.overrideWithValue(storage)],
      );
      expect(
        restarted.read(appSettingsProvider).tunApplicationRouting,
        policy(),
      );
      restarted.dispose();
    },
  );

  testWidgets(
    'manual path/action edits support missing executables, reject duplicates, and can delete a rule',
    (tester) async {
      await showSection(tester);
      await tapToolKey(tester, 'tun-app-add');
      tester
          .widget<PortSelect<TunApplicationMatch>>(
            find.byKey(const ValueKey('tun-app-rule-match')),
          )
          .onChanged(TunApplicationMatch.processPath);
      tester
          .widget<PortSelect<TunApplicationAction>>(
            find.byKey(const ValueKey('tun-app-rule-action')),
          )
          .onChanged(TunApplicationAction.block);
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('tun-app-target')),
        r'D:\Not Installed\Browser.exe',
      );
      await tapToolKey(tester, 'tun-app-rule-save');
      final rule = policy().rules.single;
      expect(rule.match, TunApplicationMatch.processPath);
      expect(rule.action, TunApplicationAction.block);
      await tapToolKey(tester, 'tun-app-edit-${rule.identity}');
      tester
          .widget<PortSelect<TunApplicationAction>>(
            find.byKey(const ValueKey('tun-app-rule-action')),
          )
          .onChanged(TunApplicationAction.direct);
      await tester.pump();
      await tapToolKey(tester, 'tun-app-rule-save');
      expect(policy().rules.single.action, TunApplicationAction.direct);
      await tapToolKey(tester, 'tun-app-add');
      tester
          .widget<PortSelect<TunApplicationMatch>>(
            find.byKey(const ValueKey('tun-app-rule-match')),
          )
          .onChanged(TunApplicationMatch.processPath);
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('tun-app-target')),
        r'd:\not installed\BROWSER.EXE',
      );
      await tapToolKey(tester, 'tun-app-rule-save');
      expect(policy().rules.length, 1);
      expect(
        find.textContaining('Это приложение уже добавлено'),
        findsOneWidget,
      );
      await tapToolKey(tester, 'tun-app-delete-${rule.identity}');
      expect(policy().rules, isEmpty);
      await tester.pump(
        const Duration(seconds: 5),
      ); // Let the existing toast expire.
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'process snapshot selection survives empty refresh and rule disabling keeps the saved identity',
    (tester) async {
      await showSection(tester);
      await tapToolKey(tester, 'tun-app-processes');
      expect(catalog.calls, 1);
      await tester.enterText(
        find.byKey(const ValueKey('tun-app-process-filter')),
        'BROWSER',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('tun-app-process-player.exe')),
        findsNothing,
      );
      tester
          .widget<PortSwitch>(
            find.byKey(const ValueKey('tun-app-process-browser.exe')),
          )
          .onChanged!(true);
      await tester.pump();
      expect(policy().rules.single.value, 'Browser.exe');
      expect(policy().rules.single.action, TunApplicationAction.direct);
      expect(
        (policy().toJson() as Map)['rules'].toString(),
        isNot(contains('processId')),
      );
      catalog.applications = [];
      await tester.ensureVisible(find.text('Обновить'));
      await tester.tap(find.text('Обновить'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ничего не найдено'), findsOneWidget);
      expect(policy().rules.single.enabled, true);
      await tester.ensureVisible(find.text('Готово'));
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      final rule = policy().rules.single;
      tester
          .widget<PortSwitch>(
            find.byKey(ValueKey('tun-app-rule-${rule.identity}')),
          )
          .onChanged!(false);
      await tester.pump();
      expect(policy().rules.single.value, 'Browser.exe');
      expect(policy().rules.single.enabled, false);
      expect(storage.current.tunApplicationRouting.rules.single.enabled, false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'JSON editor rejects malformed data, preserves concurrent/unrelated edits and repairs an invalid section',
    (tester) async {
      storage.current = AppSettings.fromJson({
        'language': 'en',
        'homeBackground': 'globe',
        'tunApplicationRouting': {
          'enabled': true,
          'rules': [
            {'processName': 'x.exe', 'action': 'typo'},
          ],
        },
      });
      await showSection(tester);
      expect(policy().validationError, isNotNull);
      await tapToolKey(tester, 'tun-app-json');
      await tester.enterText(
        find.byKey(const ValueKey('tun-app-json-text')),
        '{broken',
      );
      await tapToolKey(tester, 'tun-app-json-save');
      expect(storage.saved, isEmpty);
      final valid = {
        'enabled': true,
        'mode': 'whitelist',
        'rules': [
          {'processName': 'NeverStarted.exe', 'action': 'proxy'},
          {'processName': 'Blocked.exe', 'action': 'block', 'enabled': false},
        ],
      };
      await tester.enterText(
        find.byKey(const ValueKey('tun-app-json-text')),
        jsonEncode(valid),
      );
      container
          .read(appSettingsProvider.notifier)
          .update((settings) => settings.copyWith(pingAllOnStartup: true));
      await tapToolKey(tester, 'tun-app-json-save');
      expect(policy().validationError, isNull);
      expect(policy().toJson(), TunApplicationRouting.fromJson(valid).toJson());
      expect(storage.current.pingAllOnStartup, true);
      expect(storage.current.language, AppLanguage.en);
      expect(storage.current.homeBackground, HomeBackground.globe);
      await tapToolKey(tester, 'tun-app-json');
      container
          .read(appSettingsProvider.notifier)
          .update(
            (settings) => settings.copyWith(
              tunApplicationRouting: settings.tunApplicationRouting.copyWith(
                mode: TunApplicationRoutingMode.blacklist,
              ),
            ),
          );
      await tapToolKey(tester, 'tun-app-json-save');
      expect(find.textContaining('Правила изменились'), findsOneWidget);
      expect(policy().mode, TunApplicationRoutingMode.blacklist);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'save failure is visible and never updates the published settings state',
    (tester) async {
      await showSection(tester);
      final before = container.read(appSettingsProvider);
      storage.failSave = true;
      tester
          .widget<PortSwitch>(
            find.byKey(const ValueKey('tun-app-routing-enabled')),
          )
          .onChanged!(true);
      await tester.pumpAndSettle();
      expect(container.read(appSettingsProvider), same(before));
      expect(storage.current, same(before));
      expect(
        find.textContaining('Не удалось сохранить правила'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'late process snapshot and process errors cannot update a disposed dialog',
    (tester) async {
      final hold = Completer<List<RunningApplication>>();
      catalog.hold = hold.future;
      await showSection(tester);
      await tapToolKey(tester, 'tun-app-processes');
      expect(find.text('Чтение процессов…'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      hold.completeError(StateError('Fixture disappeared process'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
