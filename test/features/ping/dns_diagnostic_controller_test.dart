import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/core_abstraction/app_settings.dart';
import 'package:flux/core_abstraction/app_settings_provider.dart';
import 'package:flux/core_abstraction/app_settings_storage.dart';
import 'package:flux/features/connection/connection_controller.dart';
import 'package:flux/features/connection/connection_state.dart';
import 'package:flux/features/ping/dns_diagnostic_controller.dart';
import 'package:flux/features/ping/dns_diagnostic_service.dart';

import '../updates/app_update_controller_test.dart' show FakeConnection;
import 'dns_diagnostic_service_test.dart'
    show ScriptedDnsProbe, HeldDnsDiagnosticService, successfulDiagnosticReport;

class FailingDnsSettingsStorage extends AppSettingsStorage {
  const FailingDnsSettingsStorage();
  @override
  AppSettings load() => const AppSettings();
  @override
  void save(AppSettings settings) =>
      throw const FileSystemException('Synthetic save failure');
}

void main() {
  late Directory directory;
  late File settingsFile;
  late ProviderContainer container;
  late FakeConnection connection;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nn4k-dns-controller-');
    settingsFile = File('${directory.path}/settings.json');
    AppSettingsStorage(
      file: settingsFile,
    ).save(const AppSettings(onboardingCompleted: true));
    connection = FakeConnection([]);
  });

  tearDown(() async {
    container.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  ProviderContainer create(
    DnsDiagnosticService service, {
    AppSettingsStorage? storage,
  }) => container = ProviderContainer(
    overrides: [
      appSettingsStorageProvider.overrideWithValue(
        storage ?? AppSettingsStorage(file: settingsFile),
      ),
      dnsDiagnosticServiceProvider.overrideWithValue(service),
      dnsDiagnosticSupportedProvider.overrideWithValue(true),
      connectionControllerProvider.overrideWith(() => connection),
    ],
  );
  DnsDiagnosticController controller() =>
      container.read(dnsDiagnosticControllerProvider.notifier);
  DnsDiagnosticState state() => container.read(dnsDiagnosticControllerProvider);

  test('needs explicit confirmation and never starts a VPN engine', () async {
    final service = HeldDnsDiagnosticService(successfulDiagnosticReport());
    create(service);
    await controller().start(confirmed: false);
    expect(service.calls, 0);
    expect(state().phase, DnsDiagnosticPhase.idle);
    expect(connection.events, isEmpty);
  });

  test(
    'persists both fastest measured addresses atomically and restores them after reopening',
    () async {
      create(
        DnsDiagnosticService(
          probe: ScriptedDnsProbe(
            dotSamples: {
              '77.88.8.8': [40, 40, 40],
              '77.88.8.1': [15, 15, 15],
            },
          ),
        ),
      );
      await controller().start(confirmed: true);
      expect(state().phase, DnsDiagnosticPhase.completed);
      expect(container.read(appSettingsProvider).tunDnsServer, '77.88.8.1');
      expect(
        container.read(appSettingsProvider).tunDnsSecondaryServer,
        '77.88.8.8',
      );
      final json =
          jsonDecode(await settingsFile.readAsString()) as Map<String, dynamic>;
      expect(json['tunDnsServer'], '77.88.8.1');
      expect(json['tunDnsSecondaryServer'], '77.88.8.8');
      expect(container.read(appSettingsProvider).onboardingCompleted, true);
      expect(connection.events, isEmpty);
      container.dispose();
      container = ProviderContainer(
        overrides: [
          appSettingsStorageProvider.overrideWithValue(
            AppSettingsStorage(file: settingsFile),
          ),
        ],
      );
      expect(container.read(appSettingsProvider).tunDnsServer, '77.88.8.1');
      expect(
        container.read(appSettingsProvider).tunDnsSecondaryServer,
        '77.88.8.8',
      );
    },
  );

  test(
    'no eligible DNS pair leaves the previous file byte-for-byte unchanged',
    () async {
      create(DnsDiagnosticService(probe: ScriptedDnsProbe()));
      final previous = await settingsFile.readAsString();
      await controller().start(confirmed: true);
      expect(state().phase, DnsDiagnosticPhase.noWorkingPair);
      expect(await settingsFile.readAsString(), previous);
    },
  );

  test(
    'active/connecting VPN blocks diagnostics before any network probe',
    () async {
      final service = HeldDnsDiagnosticService(successfulDiagnosticReport());
      create(service);
      container.read(connectionControllerProvider);
      connection.setState(const ConnectionConnecting());
      await controller().start(confirmed: true);
      expect(service.calls, 0);
      expect(state().phase, DnsDiagnosticPhase.vpnActive);
    },
  );

  test(
    'cancel does not save a last-moment winner and duplicate starts are ignored',
    () async {
      final service = HeldDnsDiagnosticService(successfulDiagnosticReport());
      create(service);
      final previous = await settingsFile.readAsString();
      final running = controller().start(confirmed: true);
      await service.started.future;
      await controller().start(confirmed: true);
      expect(service.calls, 1);
      controller().cancel();
      expect(state().phase, DnsDiagnosticPhase.cancelling);
      service.finish.complete();
      await running;
      expect(state().phase, DnsDiagnosticPhase.cancelled);
      expect(await settingsFile.readAsString(), previous);
    },
  );

  test(
    'starting VPN during diagnostics cancels the owned probe and keeps DNS unchanged',
    () async {
      final service = HeldDnsDiagnosticService(successfulDiagnosticReport());
      create(service);
      final running = controller().start(confirmed: true);
      await service.started.future;
      connection.setState(const ConnectionConnecting());
      expect(service.cancellation!.cancelled, true);
      service.finish.complete();
      await running;
      expect(state().phase, DnsDiagnosticPhase.vpnActive);
      expect(
        container.read(appSettingsProvider).tunDnsServer,
        defaultTunDnsServer,
      );
    },
  );

  test('manual DNS changes during diagnostics are never overwritten', () async {
    final service = HeldDnsDiagnosticService(successfulDiagnosticReport());
    create(service);
    final running = controller().start(confirmed: true);
    await service.started.future;
    container
        .read(appSettingsProvider.notifier)
        .update((settings) => settings.copyWith(tunDnsServer: '1.1.1.1'));
    service.finish.complete();
    await running;
    expect(state().phase, DnsDiagnosticPhase.settingsChanged);
    expect(container.read(appSettingsProvider).tunDnsServer, '1.1.1.1');
    expect(container.read(appSettingsProvider).tunDnsSecondaryServer, '');
  });

  test(
    'unrelated new appearance preferences survive automatic DNS persistence',
    () async {
      final service = HeldDnsDiagnosticService(successfulDiagnosticReport());
      create(service);
      final running = controller().start(confirmed: true);
      await service.started.future;
      container
          .read(appSettingsProvider.notifier)
          .update(
            (settings) => settings.copyWith(
              language: AppLanguage.en,
              homeBackground: HomeBackground.none,
            ),
          );
      expect(service.cancellation!.cancelled, false);
      service.finish.complete();
      await running;
      expect(state().phase, DnsDiagnosticPhase.completed);
      expect(container.read(appSettingsProvider).language, AppLanguage.en);
      expect(
        container.read(appSettingsProvider).homeBackground,
        HomeBackground.none,
      );
    },
  );

  test('a storage failure is not reported as a saved selection', () async {
    final service = HeldDnsDiagnosticService(successfulDiagnosticReport());
    create(service, storage: const FailingDnsSettingsStorage());
    final running = controller().start(confirmed: true);
    await service.started.future;
    service.finish.complete();
    await running;
    expect(state().phase, DnsDiagnosticPhase.storageError);
    expect(
      container.read(appSettingsProvider).tunDnsServer,
      defaultTunDnsServer,
    );
    expect(container.read(appSettingsProvider).tunDnsSecondaryServer, '');
  });

  test(
    'app/container disposal cancels work and cannot save through a dead provider',
    () async {
      final service = HeldDnsDiagnosticService(successfulDiagnosticReport());
      create(service);
      final previous = await settingsFile.readAsString();
      final running = controller().start(confirmed: true);
      await service.started.future;
      container.dispose();
      expect(service.cancellation!.cancelled, true);
      service.finish.complete();
      await running;
      expect(await settingsFile.readAsString(), previous);
      // Give tearDown a fresh disposable container, without real user storage.
      container = ProviderContainer();
    },
  );
}
