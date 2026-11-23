import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core_abstraction/app_settings_provider.dart';
import '../connection/connection_controller.dart';
import '../connection/connection_state.dart';
import 'dns_diagnostic_service.dart';

enum DnsDiagnosticPhase {
  idle,
  running,
  cancelling,
  completed,
  noWorkingPair,
  cancelled,
  vpnActive,
  settingsChanged,
  storageError,
  failed,
}

class DnsDiagnosticState {
  final DnsDiagnosticPhase phase;
  final DnsDiagnosticProgress? progress;
  final DnsDiagnosticReport? report;
  const DnsDiagnosticState({
    this.phase = DnsDiagnosticPhase.idle,
    this.progress,
    this.report,
  });
  bool get busy =>
      phase == DnsDiagnosticPhase.running ||
      phase == DnsDiagnosticPhase.cancelling;
}

final dnsDiagnosticSupportedProvider = Provider<bool>(
  (_) => Platform.isWindows,
);
final dnsDiagnosticServiceProvider = Provider<DnsDiagnosticService>(
  (_) => DnsDiagnosticService(),
);
final dnsDiagnosticControllerProvider =
    NotifierProvider<DnsDiagnosticController, DnsDiagnosticState>(
      DnsDiagnosticController.new,
    );

class DnsDiagnosticController extends Notifier<DnsDiagnosticState> {
  DnsDiagnosticCancellation? _cancellation;
  DnsDiagnosticPhase _cancelReason = DnsDiagnosticPhase.cancelled;
  bool _disposed = false;
  bool _applying = false;

  @override
  DnsDiagnosticState build() {
    ref.onDispose(() {
      _disposed = true;
      _cancellation?.cancel();
    });
    ref.listen(connectionControllerProvider, (_, next) {
      if (next is! ConnectionIdle) cancel(reason: DnsDiagnosticPhase.vpnActive);
    });
    ref.listen(appSettingsProvider, (previous, next) {
      if (!_applying &&
          previous != null &&
          (previous.tunDnsServer != next.tunDnsServer ||
              previous.tunDnsSecondaryServer != next.tunDnsSecondaryServer)) {
        cancel(reason: DnsDiagnosticPhase.settingsChanged);
      }
    });
    return const DnsDiagnosticState();
  }

  Future<void> start({required bool confirmed}) async {
    if (!confirmed ||
        _disposed ||
        _cancellation != null ||
        !ref.read(dnsDiagnosticSupportedProvider)) {
      return;
    }
    if (ref.read(connectionControllerProvider) is! ConnectionIdle) {
      state = const DnsDiagnosticState(phase: DnsDiagnosticPhase.vpnActive);
      return;
    }
    final original = ref.read(appSettingsProvider);
    final cancellation = DnsDiagnosticCancellation();
    _cancellation = cancellation;
    _cancelReason = DnsDiagnosticPhase.cancelled;
    state = const DnsDiagnosticState(phase: DnsDiagnosticPhase.running);
    try {
      final report = await ref
          .read(dnsDiagnosticServiceProvider)
          .run(
            cancellation: cancellation,
            onProgress: (progress) {
              if (!_disposed && !cancellation.cancelled) {
                state = DnsDiagnosticState(
                  phase: DnsDiagnosticPhase.running,
                  progress: progress,
                );
              }
            },
          );
      cancellation.check();
      if (_disposed) return;
      final current = ref.read(appSettingsProvider);
      if (ref.read(connectionControllerProvider) is! ConnectionIdle) {
        state = DnsDiagnosticState(
          phase: DnsDiagnosticPhase.vpnActive,
          report: report,
        );
        return;
      }
      if (current.tunDnsServer != original.tunDnsServer ||
          current.tunDnsSecondaryServer != original.tunDnsSecondaryServer) {
        state = DnsDiagnosticState(
          phase: DnsDiagnosticPhase.settingsChanged,
          report: report,
        );
        return;
      }
      final selected = report.selected;
      if (selected == null) {
        state = DnsDiagnosticState(
          phase: DnsDiagnosticPhase.noWorkingPair,
          report: report,
        );
        return;
      }
      try {
        _applying = true;
        // The existing controller saves atomically BEFORE changing its state.
        // Save failure must never be presented as a persisted DNS selection.
        ref
            .read(appSettingsProvider.notifier)
            .update(
              (settings) => settings.copyWith(
                tunDnsServer: selected.primary.address,
                tunDnsSecondaryServer: selected.secondary.address,
              ),
            );
      } catch (_) {
        state = DnsDiagnosticState(
          phase: DnsDiagnosticPhase.storageError,
          report: report,
        );
        return;
      } finally {
        _applying = false;
      }
      state = DnsDiagnosticState(
        phase: DnsDiagnosticPhase.completed,
        report: report,
      );
    } on DnsDiagnosticCancelled {
      if (!_disposed) {
        state = DnsDiagnosticState(
          phase: _cancelReason,
          progress: state.progress,
        );
      }
    } catch (_) {
      if (!_disposed) {
        state = const DnsDiagnosticState(phase: DnsDiagnosticPhase.failed);
      }
    } finally {
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  void cancel({
    DnsDiagnosticPhase reason = DnsDiagnosticPhase.cancelled,
    bool notify = true,
  }) {
    if (_disposed || _cancellation == null || _cancellation!.cancelled) return;
    _cancelReason = reason;
    _cancellation!.cancel();
    if (notify) {
      state = DnsDiagnosticState(
        phase: DnsDiagnosticPhase.cancelling,
        progress: state.progress,
      );
    }
  }
}
