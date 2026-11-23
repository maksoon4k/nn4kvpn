import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/core_abstraction/app_settings.dart';
import 'package:flux/core_abstraction/app_settings_provider.dart';
import 'package:flux/features/connection/connection_controller.dart';
import 'package:flux/features/connection/connection_state.dart';
import 'package:flux/features/ping/dns_diagnostic_controller.dart';
import 'package:flux/features/ping/dns_diagnostic_section.dart';
import 'package:flux/l10n/app_locale.dart';
import 'package:flux/widgets/port_ui/port_ui.dart';

import '../updates/app_update_controller_test.dart'
    show FakeConnection, MemorySettings;
import 'dns_diagnostic_service_test.dart'
    show HeldDnsDiagnosticService, successfulDiagnosticReport;

void main() {
  setUp(() => AppLocale.effective = AppLanguage.ru);

  Future<ProviderContainer> mount(
    WidgetTester tester,
    HeldDnsDiagnosticService service, {
    FakeConnection? connection,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(
            () => MemorySettings(const AppSettings()),
          ),
          connectionControllerProvider.overrideWith(
            () => connection ?? FakeConnection([]),
          ),
          dnsDiagnosticServiceProvider.overrideWithValue(service),
          dnsDiagnosticSupportedProvider.overrideWithValue(true),
        ],
        child: const PortApp(
          home: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: DnsDiagnosticSection(),
            ),
          ),
        ),
      ),
    );
    return ProviderScope.containerOf(
      tester.element(find.byType(DnsDiagnosticSection)),
    );
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) async {
    await tap(tester, 'dns-diagnostics');
    await tap(tester, 'confirm-dns-consent');
  }

  testWidgets(
    'diagnostics asks consent; declining starts no probes or writes',
    (tester) async {
      final service = HeldDnsDiagnosticService(successfulDiagnosticReport());
      final container = await mount(tester, service);
      await tap(tester, 'dns-diagnostics');
      expect(
        find.textContaining('Начать диагностику и автоматически сохранить'),
        findsOneWidget,
      );
      expect(service.calls, 0);
      await tap(tester, 'cancel-dns-consent');
      expect(service.calls, 0);
      expect(
        container.read(appSettingsProvider).tunDnsServer,
        defaultTunDnsServer,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmed diagnostics displays progress, cancellation and persistent chosen pair',
    (tester) async {
      final service = HeldDnsDiagnosticService(successfulDiagnosticReport());
      final container = await mount(tester, service);
      await start(tester);
      expect(service.calls, 1);
      expect(find.textContaining('1/126'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('cancel-dns-diagnostics')),
        findsOneWidget,
      );
      service.finish.complete();
      await tester.pumpAndSettle();
      expect(container.read(appSettingsProvider).tunDnsServer, '77.88.8.1');
      expect(
        container.read(appSettingsProvider).tunDnsSecondaryServer,
        '77.88.8.8',
      );
      expect(find.textContaining('Выбрана Yandex'), findsOneWidget);
      await tap(tester, 'close-dns-diagnostics');
      expect(
        find.text('Сохранённый DNS: 77.88.8.1 / 77.88.8.8'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closing the dialog cancels immediately, before the reverse animation can save DNS',
    (tester) async {
      final service = HeldDnsDiagnosticService(successfulDiagnosticReport());
      final container = await mount(tester, service);
      await start(tester);
      await tester.tapAt(const Offset(4, 4));
      // Complete before pumping the dialog's 200ms closing animation.
      expect(service.cancellation!.cancelled, true);
      service.finish.complete();
      await tester.pumpAndSettle();
      expect(
        container.read(appSettingsProvider).tunDnsServer,
        defaultTunDnsServer,
      );
      expect(container.read(appSettingsProvider).tunDnsSecondaryServer, '');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel remains accessible in a narrow window and preserves DNS',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = HeldDnsDiagnosticService(successfulDiagnosticReport());
      final container = await mount(tester, service);
      await start(tester);
      await tap(tester, 'cancel-dns-diagnostics');
      expect(service.cancellation!.cancelled, true);
      service.finish.complete();
      await tester.pumpAndSettle();
      expect(find.text('Отменено. Прежний DNS не изменён.'), findsOneWidget);
      expect(
        container.read(appSettingsProvider).tunDnsServer,
        defaultTunDnsServer,
      );
      await tap(tester, 'close-dns-diagnostics');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'connecting VPN disables the section without starting diagnostics',
    (tester) async {
      final service = HeldDnsDiagnosticService(successfulDiagnosticReport());
      final connection = FakeConnection([]);
      await mount(tester, service, connection: connection);
      connection.setState(const ConnectionConnecting());
      await tester.pump();
      expect(
        tester
            .widget<PortButton>(find.byKey(const ValueKey('dns-diagnostics')))
            .onPressed,
        isNull,
      );
      expect(service.calls, 0);
      expect(
        find.textContaining('Перед диагностикой выключите VPN'),
        findsOneWidget,
      );
    },
  );
}
