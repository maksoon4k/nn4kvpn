import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/core_abstraction/app_settings.dart';
import 'package:flux/core_abstraction/app_settings_provider.dart';
import 'package:flux/core_abstraction/connection_session.dart';
import 'package:flux/features/connection/connection_controller.dart';
import 'package:flux/features/connection/connection_state.dart';
import 'package:flux/features/updates/app_update_controller.dart';
import 'package:flux/features/updates/github_release.dart';
import 'package:flux/features/updates/github_update_service.dart';
import 'package:flux/features/updates/windows_update_installer.dart';
import 'package:flux/features/updates/windows_update_token_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'github_release_test.dart' show releaseFixture;
import 'github_update_service_test.dart'
    show downloadableFixture, fixtureInstaller;

void main() {
  late ProviderContainer container;
  late Directory directory;
  late MemoryTokenStore tokens;
  late FakeConnection connection;
  late FakeInstaller installer;
  late List<String> events;
  late Map<String, dynamic> releaseJson;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nn4k-controller-tests-');
    tokens = MemoryTokenStore();
    events = [];
    connection = FakeConnection(events);
    releaseJson = releaseFixture();
    final fixture = downloadableFixture();
    (releaseJson['assets'] as List).first
      ..['size'] = fixture.installer.size
      ..['digest'] = 'sha256:${fixture.installer.sha256}';
    final service = GitHubUpdateService(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/latest')) {
          return http.Response(jsonEncode(releaseJson), 200);
        }
        return http.Response.bytes(fixtureInstaller, 200);
      }),
    );
    installer = FakeInstaller(service, events);
    container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWith(
          () =>
              MemorySettings(const AppSettings(updateRepository: 'owner/nn4k')),
        ),
        connectionControllerProvider.overrideWith(() => connection),
        updateTokenStoreProvider.overrideWithValue(tokens),
        githubUpdateServiceProvider.overrideWithValue(service),
        updateInstallerProvider.overrideWithValue(installer),
        updateCurrentVersionProvider.overrideWith((_) async => '1.9.0'),
        updateDownloadDirectoryProvider.overrideWithValue(directory),
        updateExitAppProvider.overrideWithValue(() => events.add('exit')),
      ],
    );
    addTearDown(service.close);
  });

  tearDown(() async {
    container.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  AppUpdateController controller() =>
      container.read(appUpdateControllerProvider.notifier);
  AppUpdateState state() => container.read(appUpdateControllerProvider);

  test(
    'checks and downloads, without launching any installer or VPN engine',
    () async {
      await controller().check();
      expect(state().phase, AppUpdatePhase.available);
      await controller().download();
      expect(state().phase, AppUpdatePhase.ready);
      expect(state().hasDownloaded, true);
      expect(events, isEmpty);
    },
  );

  test('stops the connection before launching and only then exits', () async {
    await controller().check();
    await controller().install();
    expect(events, ['validate', 'prepareForExit', 'launch', 'exit']);
  });

  test('automatic installation stays opt-in', () async {
    await controller().check();
    await controller().install(automatic: true);
    expect(state().phase, AppUpdatePhase.available);
    expect(await directory.list().toList(), isEmpty);
    expect(events, isEmpty);
  });

  test('automatic installation does not disconnect an active VPN', () async {
    container
        .read(appSettingsProvider.notifier)
        .update((settings) => settings.copyWith(autoInstallUpdates: true));
    container.read(connectionControllerProvider);
    connection.setState(
      ConnectionConnected(
        leafId: 'fixture',
        variantId: 'fixture',
        serverName: 'Fixture',
        connectedAt: DateTime(2026),
        mode: ConnectionMode.proxy,
      ),
    );
    await controller().check();
    await controller().install(automatic: true);
    expect(state().phase, AppUpdatePhase.ready);
    expect(events, isEmpty);
    expect(
      container.read(connectionControllerProvider),
      isA<ConnectionConnected>(),
    );
  });

  test('re-checks idle state after asynchronous validation', () async {
    container
        .read(appSettingsProvider.notifier)
        .update((settings) => settings.copyWith(autoInstallUpdates: true));
    await controller().check();
    await controller().download();
    final hold = Completer<void>();
    installer.validationHold = hold.future;
    final installing = controller().install(automatic: true);
    await installer.validationStarted.future;
    connection.setState(const ConnectionConnecting());
    hold.complete();
    await installing;
    expect(events, ['validate']);
    expect(state().phase, AppUpdatePhase.ready);
  });

  test('elevated/invalid updates never disconnect or exit the app', () async {
    installer.validationFailure = UpdateFailure.elevated;
    await controller().check();
    await controller().install();
    expect(events, ['validate']);
    expect(state().failure, UpdateFailure.elevated);
    expect(state().hasDownloaded, true);
  });

  test(
    'installer launch failure keeps the app open and unlocks reconnection',
    () async {
      installer.launchFailure = true;
      await controller().check();
      await controller().install();
      expect(events, ['validate', 'prepareForExit', 'launch', 'cancelExit']);
      expect(state().failure, UpdateFailure.installFailed);
      expect(state().hasDownloaded, true);
    },
  );

  test(
    'tampering after download prevents installation and invalidates the cache',
    () async {
      await controller().check();
      await controller().download();
      final file = await directory
          .list(recursive: true)
          .where((entity) => entity is File)
          .first;
      await File(file.path).writeAsBytes([0x4d, 0x5a, 9, 9, 9, 9, 9, 9]);
      await controller().install();
      expect(events, ['validate']);
      expect(state().failure, UpdateFailure.checksumMismatch);
      expect(state().hasDownloaded, false);
    },
  );

  test(
    'a replaced same-version GitHub asset invalidates the downloaded file',
    () async {
      await controller().check();
      await controller().download();
      (releaseJson['assets'] as List).first['id'] = 999;
      await controller().check();
      expect(state().phase, AppUpdatePhase.available);
      expect(state().hasDownloaded, false);
    },
  );

  test(
    'configuration stores a per-repository credential, not a JSON token',
    () async {
      await controller().configure(
        'https://github.com/owner/nn4k',
        token: 'fixture_read_only_token',
      );
      expect(tokens.values, {'owner/nn4k': 'fixture_read_only_token'});
      expect(
        jsonEncode(container.read(appSettingsProvider).toJson()),
        isNot(contains('fixture_read_only_token')),
      );
      expect(state().hasToken, true);
      await controller().configure('owner/nn4k'); // Blank preserves the token.
      expect(state().hasToken, true);
      await controller().configure('owner/nn4k', removeToken: true);
      expect(tokens.values, isEmpty);
      expect(state().hasToken, false);
    },
  );

  test(
    'changing repositories requires new automatic-install consent',
    () async {
      container
          .read(appSettingsProvider.notifier)
          .update((settings) => settings.copyWith(autoInstallUpdates: true));
      await controller().configure('other/nn4k');
      expect(container.read(appSettingsProvider).autoInstallUpdates, false);
      expect(state().release, isNull);
    },
  );

  test(
    'changing repositories during shutdown cancels launch and unlocks VPN',
    () async {
      await controller().check();
      final hold = Completer<void>();
      connection.prepareHold = hold.future;
      final installing = controller().install();
      await connection.prepareStarted.future;
      container
          .read(appSettingsProvider.notifier)
          .update(
            (settings) => settings.copyWith(updateRepository: 'other/nn4k'),
          );
      hold.complete();
      await installing;
      expect(events, ['validate', 'prepareForExit', 'cancelExit']);
      expect(state().phase, AppUpdatePhase.idle);
      expect(state().release, isNull);
    },
  );

  test(
    'withdrawing auto-install consent during final validation cancels launch',
    () async {
      container
          .read(appSettingsProvider.notifier)
          .update((settings) => settings.copyWith(autoInstallUpdates: true));
      await controller().check();
      final hold = Completer<void>();
      installer.launchHold = hold.future;
      final installing = controller().install(automatic: true);
      await installer.launchStarted.future;
      container
          .read(appSettingsProvider.notifier)
          .update((settings) => settings.copyWith(autoInstallUpdates: false));
      hold.complete();
      await installing;
      expect(events, ['validate', 'prepareForExit', 'cancelExit']);
      expect(state().phase, AppUpdatePhase.ready);
    },
  );

  test(
    'changing repositories during final validation cancels launch',
    () async {
      await controller().check();
      final hold = Completer<void>();
      installer.launchHold = hold.future;
      final installing = controller().install();
      await installer.launchStarted.future;
      container
          .read(appSettingsProvider.notifier)
          .update(
            (settings) => settings.copyWith(updateRepository: 'other/nn4k'),
          );
      hold.complete();
      await installing;
      expect(events, ['validate', 'prepareForExit', 'cancelExit']);
      expect(state().phase, AppUpdatePhase.idle);
    },
  );

  test(
    'a stale check cannot re-enable an update from the previous repository',
    () async {
      final response = Completer<http.Response>();
      final requested = Completer<void>();
      final service = GitHubUpdateService(
        client: MockClient((_) async {
          requested.complete();
          return response.future;
        }),
      );
      final isolated = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(
            () => MemorySettings(
              const AppSettings(updateRepository: 'owner/nn4k'),
            ),
          ),
          updateTokenStoreProvider.overrideWithValue(tokens),
          githubUpdateServiceProvider.overrideWithValue(service),
          updateCurrentVersionProvider.overrideWith((_) async => '1.9.0'),
        ],
      );
      addTearDown(() {
        isolated.dispose();
        service.close();
      });
      final checking = isolated
          .read(appUpdateControllerProvider.notifier)
          .check();
      await requested.future;
      isolated
          .read(appSettingsProvider.notifier)
          .update(
            (settings) => settings.copyWith(updateRepository: 'other/nn4k'),
          );
      response.complete(http.Response(jsonEncode(releaseJson), 200));
      await checking;
      expect(
        isolated.read(appUpdateControllerProvider).phase,
        AppUpdatePhase.idle,
      );
      expect(isolated.read(appUpdateControllerProvider).release, isNull);
    },
  );
}

class MemorySettings extends AppSettingsController {
  final AppSettings initial;
  MemorySettings(this.initial);
  @override
  AppSettings build() => initial;
  @override
  void update(AppSettings Function(AppSettings) transform) =>
      state = transform(state);
}

class MemoryTokenStore implements UpdateTokenStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String repository) async => values[repository];
  @override
  Future<void> write(String repository, String token) async =>
      values[repository] = token;
  @override
  Future<void> delete(String repository) async => values.remove(repository);
}

class FakeConnection extends ConnectionController {
  final List<String> events;
  final prepareStarted = Completer<void>();
  Future<void>? prepareHold;
  FakeConnection(this.events);
  @override
  ConnectionUiState build() => const ConnectionIdle();
  void setState(ConnectionUiState value) => state = value;
  @override
  Future<void> prepareForExit() async {
    events.add('prepareForExit');
    if (!prepareStarted.isCompleted) prepareStarted.complete();
    await prepareHold;
    state = const ConnectionIdle();
  }

  @override
  void cancelExit() => events.add('cancelExit');
}

class FakeInstaller implements UpdateInstaller {
  final GitHubUpdateService service;
  final List<String> events;
  final validationStarted = Completer<void>();
  final launchStarted = Completer<void>();
  UpdateFailure? validationFailure;
  Future<void>? validationHold;
  Future<void>? launchHold;
  bool launchFailure = false;
  FakeInstaller(this.service, this.events);
  @override
  Future<void> validate(DownloadedUpdate update) async {
    events.add('validate');
    if (!validationStarted.isCompleted) validationStarted.complete();
    await validationHold;
    if (validationFailure != null) throw UpdateException(validationFailure!);
    await service.verifyDownloaded(update);
  }

  @override
  Future<bool> launch(
    DownloadedUpdate update, {
    bool Function()? shouldLaunch,
  }) async {
    if (!launchStarted.isCompleted) launchStarted.complete();
    await launchHold;
    if (shouldLaunch != null && !shouldLaunch()) return false;
    events.add('launch');
    if (launchFailure) throw const UpdateException(UpdateFailure.installFailed);
    return true;
  }
}
