import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/app/app_title_bar.dart';
import 'package:flux/core_abstraction/app_settings.dart';
import 'package:flux/core_abstraction/app_settings_provider.dart';
import 'package:flux/core_abstraction/core_config.dart';
import 'package:flux/core_abstraction/core_config_provider.dart';
import 'package:flux/features/connection/connection_screen.dart';
import 'package:flux/features/onboarding/onboarding_flow.dart';
import 'package:flux/features/onboarding/onboarding_steps.dart';
import 'package:flux/l10n/strings.dart';
import 'package:flux/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windowManagerChannel = MethodChannel('window_manager');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, (call) async {
          if (call.method == 'isMaximized') return false;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, null);
  });

  Future<_MemorySettingsController> showFirstRun(WidgetTester tester) async {
    // All configuration stays in memory; no profiles, registry writes,
    // autostart selection, network requests or live VPN controls are used.
    final settings = _MemorySettingsController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(() => settings),
          coreConfigProvider.overrideWith(_EmptyCoreConfigController.new),
        ],
        child: FluxApp(
          navigatorKey: GlobalKey<NavigatorState>(),
          incomingDeepLinks: const Stream.empty(),
          safeStart: true,
        ),
      ),
    );
    return settings;
  }

  Future<void> tapAndAdvance(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    // Background previews animate continuously; do not pumpAndSettle them.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('the first-run welcome takes priority over opening settings', (
    tester,
  ) async {
    final settings = await showFirstRun(tester);
    expect(find.byType(WelcomeStep), findsOneWidget);
    expect(find.text(S.onboardingWelcomeTitle), findsOneWidget);
    expect(find.byType(ConnectionScreen), findsNothing);
    expect(settings.current.onboardingCompleted, isFalse);

    tester.widget<AppTitleBar>(find.byType(AppTitleBar)).onToggleSettings();
    await tester.pump();
    expect(find.byType(OnboardingFlow), findsOneWidget);
    expect(find.byType(WelcomeStep), findsOneWidget);
    expect(settings.current.onboardingCompleted, isFalse);
  });

  testWidgets('all original setup steps remain until explicit completion', (
    tester,
  ) async {
    final settings = await showFirstRun(tester);
    await tapAndAdvance(tester, S.onboardingCustomize);
    expect(find.byType(BackgroundStep), findsOneWidget);
    expect(settings.current.homeBackground, HomeBackground.galaxy);
    expect(settings.current.onboardingCompleted, isFalse);

    await tapAndAdvance(tester, S.onboardingNext);
    expect(find.byType(LanguageStep), findsOneWidget);
    expect(settings.current.onboardingCompleted, isFalse);

    if (!Platform.isAndroid) {
      await tapAndAdvance(tester, S.onboardingNext);
      expect(find.byType(AutostartStep), findsOneWidget);
      expect(settings.current.autoStartPrivilege, AppAutoStartPrivilege.none);
    }

    await tapAndAdvance(tester, S.onboardingNext);
    expect(find.byType(GuideDemoStep), findsOneWidget);
    expect(settings.current.onboardingCompleted, isFalse);

    await tapAndAdvance(tester, S.onboardingDone);
    expect(settings.current.onboardingCompleted, isTrue);
    expect(settings.current.homeBackground, HomeBackground.galaxy);
    expect(find.byType(OnboardingFlow), findsNothing);
    expect(find.byType(ConnectionScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('skipping setup leaves existing appearance settings intact', (
    tester,
  ) async {
    final settings = await showFirstRun(tester);
    final before = settings.current;
    await tapAndAdvance(tester, S.onboardingSkip);
    expect(
      settings.current.toJson(),
      before.copyWith(onboardingCompleted: true).toJson(),
    );
    expect(find.byType(OnboardingFlow), findsNothing);
    expect(find.byType(ConnectionScreen), findsOneWidget);
  });

  testWidgets('resetting completion shows the original welcome again', (
    tester,
  ) async {
    final settings = await showFirstRun(tester);
    await tapAndAdvance(tester, S.onboardingSkip);
    settings.update((s) => s.copyWith(onboardingCompleted: false));
    await tester.pump();
    expect(find.byType(OnboardingFlow), findsOneWidget);
    expect(find.byType(WelcomeStep), findsOneWidget);
    expect(find.byType(ConnectionScreen), findsNothing);
    expect(settings.current.homeBackground, HomeBackground.galaxy);
  });
}

class _MemorySettingsController extends AppSettingsController {
  AppSettings get current => state;

  @override
  AppSettings build() => const AppSettings(language: AppLanguage.ru);

  @override
  void update(AppSettings Function(AppSettings settings) transform) {
    state = transform(state);
  }
}

class _EmptyCoreConfigController extends CoreConfigController {
  @override
  CoreConfig build() => const CoreConfig();
}
