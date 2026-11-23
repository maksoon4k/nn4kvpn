import 'package:flutter/material.dart' show TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/core_abstraction/app_settings.dart';
import 'package:flux/core_abstraction/app_settings_provider.dart';
import 'package:flux/features/updates/app_update_controller.dart';
import 'package:flux/features/updates/update_section.dart';
import 'package:flux/l10n/app_locale.dart';
import 'package:flux/widgets/port_ui/port_ui.dart';

import 'app_update_controller_test.dart' show MemorySettings;

class UiUpdateController extends AppUpdateController {
  bool checked = false;
  @override
  AppUpdateState build() => const AppUpdateState();
  @override
  Future<void> check() async {
    checked = true;
    state = const AppUpdateState(phase: AppUpdatePhase.upToDate);
  }
}

void main() {
  setUp(() => AppLocale.effective = AppLanguage.ru);

  testWidgets('check control stays in the app and shows the result', (
    tester,
  ) async {
    final controller = UiUpdateController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(
            () => MemorySettings(const AppSettings()),
          ),
          appUpdateControllerProvider.overrideWith(() => controller),
        ],
        child: const PortApp(
          home: SingleChildScrollView(
            child: Padding(padding: EdgeInsets.all(24), child: UpdateSection()),
          ),
        ),
      ),
    );
    expect(
      find.text('Обновления доступны всем — без аккаунта и токена.'),
      findsOneWidget,
    );
    expect(find.textContaining('maksoon4k'), findsNothing);
    expect(find.textContaining('nn4kvpn'), findsNothing);
    expect(find.byKey(const ValueKey('configure-updates')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('check-updates')));
    await tester.pump();
    expect(controller.checked, true);
    expect(find.text('Установлена последняя версия'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'public updates have no credential fields and fit a narrow window',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsProvider.overrideWith(
              () => MemorySettings(const AppSettings()),
            ),
            appUpdateControllerProvider.overrideWith(UiUpdateController.new),
          ],
          child: const PortApp(
            home: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: UpdateSection(),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('configure-updates')), findsNothing);
      expect(find.textContaining('GitHub'), findsNothing);
      expect(find.textContaining('maksoon4k'), findsNothing);
      expect(find.textContaining('nn4kvpn'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('check-updates')));
      await tester.pumpAndSettle();
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
