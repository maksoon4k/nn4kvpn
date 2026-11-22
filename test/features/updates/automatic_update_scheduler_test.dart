import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/core_abstraction/app_settings.dart';
import 'package:flux/core_abstraction/app_settings_provider.dart';
import 'package:flux/core_abstraction/connection_session.dart';
import 'package:flux/features/connection/connection_controller.dart';
import 'package:flux/features/connection/connection_state.dart';
import 'package:flux/features/updates/app_update_controller.dart';
import 'package:flux/features/updates/automatic_update_scheduler.dart';
import 'package:flux/features/updates/github_release.dart';

import 'app_update_controller_test.dart' show FakeConnection, MemorySettings;
import 'github_release_test.dart' show releaseFixture;

class SchedulerUpdateController extends AppUpdateController {
  final events = <String>[];
  bool checkFails = false;
  final release = GitHubRelease.fromJson(
    GitHubRepository.parse('owner/nn4k'),
    releaseFixture(),
  );
  @override
  AppUpdateState build() => const AppUpdateState();
  @override
  Future<void> check() async {
    events.add('check');
    state = AppUpdateState(
      phase: checkFails ? AppUpdatePhase.error : AppUpdatePhase.available,
      failure: checkFails ? UpdateFailure.network : null,
      release: release,
    );
  }

  @override
  Future<void> download() async {
    events.add('download');
    state = AppUpdateState(
      phase: AppUpdatePhase.ready,
      release: release,
      hasDownloaded: true,
    );
  }

  @override
  Future<void> install({bool automatic = false}) async {
    events.add('install:$automatic');
    state = const AppUpdateState();
  }
}

void main() {
  Future<void> withScheduler(
    Future<void> Function(
      ProviderContainer,
      SchedulerUpdateController,
      FakeConnection,
    )
    body, {
    bool checks = true,
    bool automatic = false,
  }) async {
    final update = SchedulerUpdateController();
    final connection = FakeConnection([]);
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWith(
          () => MemorySettings(
            AppSettings(
              updateRepository: 'owner/nn4k',
              checkForUpdatesOnStartup: checks,
              autoInstallUpdates: automatic,
            ),
          ),
        ),
        appUpdateControllerProvider.overrideWith(() => update),
        connectionControllerProvider.overrideWith(() => connection),
      ],
    );
    final scheduler = AutomaticUpdateScheduler(container)..start();
    try {
      await body(container, update, connection);
    } finally {
      scheduler.dispose();
      container.dispose();
    }
  }

  testWidgets('startup and six-hour checks never download without opt-in', (
    tester,
  ) async {
    await withScheduler((container, update, connection) async {
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(update.events, ['check']);
      await tester.pump(const Duration(hours: 6));
      await tester.pump();
      expect(update.events, ['check', 'check']);
    });
  });

  testWidgets('turning background checks off makes startup silent', (
    tester,
  ) async {
    await withScheduler((container, update, connection) async {
      await tester.pump(const Duration(seconds: 30));
      expect(update.events, isEmpty);
    }, checks: false);
  });

  testWidgets('automatic download defers installation until VPN becomes idle', (
    tester,
  ) async {
    await withScheduler((container, update, connection) async {
      connection.setState(
        ConnectionConnected(
          leafId: 'fixture',
          variantId: 'fixture',
          serverName: 'Fixture',
          connectedAt: DateTime(2026),
          mode: ConnectionMode.proxy,
        ),
      );
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(update.events, ['check', 'download']);
      connection.setState(const ConnectionIdle());
      await tester.pump();
      expect(update.events, ['check', 'download', 'install:true']);
    }, automatic: true);
  });

  testWidgets('a failed fresh check cannot automatically run a stale release', (
    tester,
  ) async {
    await withScheduler((container, update, connection) async {
      update.checkFails = true;
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(update.events, ['check']);
    }, automatic: true);
  });

  testWidgets('changing preferences reschedules the check', (tester) async {
    await withScheduler((container, update, connection) async {
      container
          .read(appSettingsProvider.notifier)
          .update(
            (settings) => settings.copyWith(checkForUpdatesOnStartup: true),
          );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(update.events, ['check']);
    }, checks: false);
  });
}
