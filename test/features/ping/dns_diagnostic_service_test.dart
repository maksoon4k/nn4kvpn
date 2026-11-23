import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux/core_abstraction/dns_resolver.dart';
import 'package:flux/features/ping/dns_diagnostic_service.dart';

class ScriptedDnsProbe implements DnsDiagnosticProbe {
  final Map<String, List<int?>> dotSamples;
  final bool echoWorks;
  final bool udpWorks;
  final calls = <(String, String, String?)>[];
  final _indices = <String, int>{};
  int active = 0;
  int maxActive = 0;

  ScriptedDnsProbe({
    this.dotSamples = const {},
    this.echoWorks = true,
    this.udpWorks = true,
  });

  Future<int?> _measure(
    String kind,
    String address,
    String? domain,
    DnsDiagnosticCancellation cancellation,
  ) async {
    cancellation.check();
    calls.add((kind, address, domain));
    active++;
    if (active > maxActive) maxActive = active;
    try {
      await Future<void>.value();
      cancellation.check();
      if (kind == 'icmp') return echoWorks ? 10 : null;
      if (kind == 'udp') return udpWorks ? 20 : null;
      final index = _indices.update(
        address,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      return (dotSamples[address] ?? const [null, null, null])[index];
    } finally {
      active--;
    }
  }

  @override
  Future<int?> icmp(String address, DnsDiagnosticCancellation cancellation) =>
      _measure('icmp', address, null, cancellation);
  @override
  Future<int?> udpDns(
    String address,
    String domain,
    DnsDiagnosticCancellation cancellation,
  ) => _measure('udp', address, domain, cancellation);
  @override
  Future<int?> dotDns(
    String address,
    String? serverName,
    String domain,
    DnsDiagnosticCancellation cancellation,
  ) {
    expect(serverName, dnsTlsServerNameFor(address));
    return _measure('dot', address, domain, cancellation);
  }
}

class HeldDnsDiagnosticService extends DnsDiagnosticService {
  final started = Completer<void>();
  final finish = Completer<void>();
  final DnsDiagnosticReport report;
  DnsDiagnosticCancellation? cancellation;
  int calls = 0;
  HeldDnsDiagnosticService(this.report);

  @override
  Future<DnsDiagnosticReport> run({
    required DnsDiagnosticCancellation cancellation,
    required void Function(DnsDiagnosticProgress) onProgress,
  }) async {
    calls++;
    this.cancellation = cancellation;
    if (!started.isCompleted) started.complete();
    onProgress(
      DnsDiagnosticProgress(
        1,
        DnsDiagnosticService.measurements,
        diagnosticDnsPairs.first.primary,
        [],
      ),
    );
    await finish.future;
    cancellation.check();
    return report;
  }
}

DnsDiagnosticReport successfulDiagnosticReport() {
  final pair = diagnosticDnsPairs.first;
  final result = DnsPairResult(
    pair,
    DnsEndpointResult(pair.primary, [10, 10, 10], [20, 20, 20], [40, 40, 40]),
    DnsEndpointResult(pair.secondary, [10, 10, 10], [20, 20, 20], [15, 15, 15]),
  );
  return DnsDiagnosticReport([result], result);
}

void main() {
  Future<DnsDiagnosticReport> diagnose(ScriptedDnsProbe probe) =>
      DnsDiagnosticService(
        probe: probe,
      ).run(cancellation: DnsDiagnosticCancellation(), onProgress: (_) {});

  test(
    'covers the exact seven pairs, sequentially, with three real DNS domains',
    () async {
      expect(diagnosticDnsPairs.map((pair) => pair.addresses), [
        ['77.88.8.8', '77.88.8.1'],
        ['1.1.1.1', '1.0.0.1'],
        ['8.8.8.8', '8.8.4.4'],
        ['9.9.9.9', '149.112.112.112'],
        ['94.140.14.14', '94.140.15.15'],
        ['208.67.222.222', '208.67.220.220'],
        ['76.76.2.0', '76.76.10.0'],
      ]);
      final probe = ScriptedDnsProbe();
      final progress = <DnsDiagnosticProgress>[];
      final report = await DnsDiagnosticService(probe: probe).run(
        cancellation: DnsDiagnosticCancellation(),
        onProgress: progress.add,
      );
      expect(probe.maxActive, 1);
      expect(probe.active, 0);
      expect(probe.calls, hasLength(126));
      expect(report.results, hasLength(7));
      var cursor = 0;
      for (final pair in diagnosticDnsPairs) {
        for (final address in pair.addresses) {
          for (final domain in DnsDiagnosticService.queryDomains) {
            expect(probe.calls[cursor++], ('icmp', address, null));
            expect(probe.calls[cursor++], ('udp', address, domain));
            expect(probe.calls[cursor++], ('dot', address, domain));
          }
        }
      }
      expect(progress.last.completed, 126);
      expect(progress.last.results, hasLength(7));
      for (var index = 1; index < progress.length; index++) {
        expect(
          progress[index].completed,
          greaterThanOrEqualTo(progress[index - 1].completed),
        );
      }
      expect(dnsTlsServerNameFor('208.67.222.222'), isNull);
      expect(dnsTlsServerNameFor('94.140.14.14'), 'dns.adguard-dns.com');
      expect(dnsTlsServerNameFor('76.76.10.0'), 'p0.freedns.controld.com');
    },
  );

  test('DNS reliability wins over faster but lossy ICMP/DoT results', () async {
    final report = await diagnose(
      ScriptedDnsProbe(
        dotSamples: {
          '77.88.8.8': [1, 1, null],
          '77.88.8.1': [1, null, 1],
          '1.1.1.1': [35, 35, 35],
          '1.0.0.1': [20, 20, 20],
        },
      ),
    );
    expect(report.selected!.pair.name, 'Cloudflare');
    expect(report.selected!.dnsSuccesses, 6);
    expect(report.selected!.primary.address, '1.0.0.1');
    expect(report.selected!.secondary.address, '1.1.1.1');
  });

  test('equal reliability is ranked by median encrypted DNS latency', () async {
    final report = await diagnose(
      ScriptedDnsProbe(
        dotSamples: {
          '77.88.8.8': [500, 50, 50],
          '77.88.8.1': [50, 50, 50],
          '1.1.1.1': [15, 15, 15],
          '1.0.0.1': [15, 15, 15],
        },
      ),
    );
    expect(report.selected!.pair.name, 'Cloudflare');
    expect(report.results.first.latency, 50);
    expect(report.selected!.primary.address, '1.1.1.1');
  });

  test('ICMP or UDP DNS alone never qualifies an encrypted resolver', () async {
    final report = await diagnose(ScriptedDnsProbe());
    expect(report.selected, isNull);
    expect(report.results.every((result) => result.icmpSuccesses == 6), true);
  });

  test('blocked ICMP does not disqualify valid encrypted DNS', () async {
    final report = await diagnose(
      ScriptedDnsProbe(
        echoWorks: false,
        dotSamples: {
          '8.8.8.8': [30, 30, 30],
          '8.8.4.4': [40, 40, 40],
        },
      ),
    );
    expect(report.selected!.pair.name, 'Google');
    expect(report.selected!.icmpSuccesses, 0);
  });

  test(
    'both addresses need two valid DoT replies, not just one working primary',
    () async {
      final report = await diagnose(
        ScriptedDnsProbe(
          dotSamples: {
            '8.8.8.8': [1, 1, 1],
            '8.8.4.4': [1, null, null],
          },
        ),
      );
      expect(report.selected, isNull);
    },
  );

  test(
    'cancel stops before the next measurement and never returns a partial winner',
    () async {
      final cancellation = DnsDiagnosticCancellation();
      final probe = ScriptedDnsProbe();
      await expectLater(
        DnsDiagnosticService(probe: probe).run(
          cancellation: cancellation,
          onProgress: (progress) {
            if (progress.completed == 11) cancellation.cancel();
          },
        ),
        throwsA(isA<DnsDiagnosticCancelled>()),
      );
      expect(probe.calls, hasLength(11));
      expect(probe.active, 0);
    },
  );

  test(
    'cancellation is idempotent, removes handlers and tolerates cleanup failures',
    () {
      final cancellation = DnsDiagnosticCancellation();
      var cleaned = 0;
      final unregister = cancellation.onCancel(() => cleaned += 100);
      unregister();
      cancellation.onCancel(
        () => throw StateError('Synthetic cleanup failure'),
      );
      cancellation.onCancel(() => cleaned++);
      cancellation.cancel();
      cancellation.cancel();
      cancellation.onCancel(() => cleaned++);
      expect(cleaned, 2);
      expect(cancellation.check, throwsA(isA<DnsDiagnosticCancelled>()));
    },
  );
}
