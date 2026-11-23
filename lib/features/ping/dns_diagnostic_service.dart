import 'dart:async';

import '../../core_abstraction/dns_resolver.dart';
import 'windows_dns_probe.dart';

class DnsDiagnosticCancelled implements Exception {
  const DnsDiagnosticCancelled();
}

class DnsDiagnosticCancellation {
  bool _cancelled = false;
  final _callbacks = <void Function()>{};
  bool get cancelled => _cancelled;

  void check() {
    if (_cancelled) throw const DnsDiagnosticCancelled();
  }

  void Function() onCancel(void Function() callback) {
    if (_cancelled) {
      try {
        callback();
      } catch (_) {
        /* Continue cancellation cleanup. */
      }
      return () {};
    }
    _callbacks.add(callback);
    return () => _callbacks.remove(callback);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final callback in _callbacks.toList()) {
      try {
        callback();
      } catch (_) {
        /* Close all owned probes, not just one. */
      }
    }
    _callbacks.clear();
  }
}

abstract interface class DnsDiagnosticProbe {
  Future<int?> icmp(String address, DnsDiagnosticCancellation cancellation);
  Future<int?> udpDns(
    String address,
    String domain,
    DnsDiagnosticCancellation cancellation,
  );
  Future<int?> dotDns(
    String address,
    String? serverName,
    String domain,
    DnsDiagnosticCancellation cancellation,
  );
}

class DnsEndpointResult {
  final String address;
  final List<int?> icmp;
  final List<int?> udp;
  final List<int?> dot;

  DnsEndpointResult(
    this.address,
    List<int?> icmp,
    List<int?> udp,
    List<int?> dot,
  ) : icmp = List.unmodifiable(icmp),
      udp = List.unmodifiable(udp),
      dot = List.unmodifiable(dot);

  int get dnsSuccesses => dot.whereType<int>().length;
  bool get reliable => dnsSuccesses >= 2;
  double? get dnsLatency => medianLatency(dot);

  static double? medianLatency(List<int?> samples) {
    final values = samples.whereType<int>().toList()..sort();
    if (values.isEmpty) return null;
    final mid = values.length ~/ 2;
    return values.length.isOdd
        ? values[mid].toDouble()
        : (values[mid - 1] + values[mid]) / 2;
  }
}

class DnsPairResult {
  final DnsResolverPair pair;
  final DnsEndpointResult first;
  final DnsEndpointResult second;
  const DnsPairResult(this.pair, this.first, this.second);

  bool get reliable => first.reliable && second.reliable;
  int get dnsSuccesses => first.dnsSuccesses + second.dnsSuccesses;
  double get latency => (first.dnsLatency! + second.dnsLatency!) / 2;
  int get icmpSuccesses =>
      first.icmp.whereType<int>().length + second.icmp.whereType<int>().length;
  DnsEndpointResult get primary =>
      _compareEndpoints(first, second) <= 0 ? first : second;
  DnsEndpointResult get secondary => identical(primary, first) ? second : first;

  static int _compareEndpoints(DnsEndpointResult a, DnsEndpointResult b) {
    final reliability = b.dnsSuccesses.compareTo(a.dnsSuccesses);
    if (reliability != 0) return reliability;
    return (a.dnsLatency ?? double.infinity).compareTo(
      b.dnsLatency ?? double.infinity,
    );
  }
}

class DnsDiagnosticProgress {
  final int completed;
  final int total;
  final String address;
  final List<DnsPairResult> results;
  DnsDiagnosticProgress(
    this.completed,
    this.total,
    this.address,
    List<DnsPairResult> results,
  ) : results = List.unmodifiable(results);
}

class DnsDiagnosticReport {
  final List<DnsPairResult> results;
  final DnsPairResult? selected;
  DnsDiagnosticReport(List<DnsPairResult> results, this.selected)
    : results = List.unmodifiable(results);
}

/// Runs only after explicit consent, with no engine, proxy or system DNS change.
/// Reliability of real certificate-verified DoT answers takes priority over
/// latency. ICMP is informational: resolvers may legitimately block echoes.
class DnsDiagnosticService {
  final DnsDiagnosticProbe probe;
  DnsDiagnosticService({DnsDiagnosticProbe? probe})
    : probe = probe ?? const WindowsDnsProbe();

  static const queryDomains = ['example.com', 'example.net', 'example.org'];
  static const measurements = 14 * 3 * 3;

  Future<DnsDiagnosticReport> run({
    required DnsDiagnosticCancellation cancellation,
    required void Function(DnsDiagnosticProgress) onProgress,
  }) async {
    final results = <DnsPairResult>[];
    var completed = 0;
    for (final pair in diagnosticDnsPairs) {
      final endpoints = <DnsEndpointResult>[];
      for (final address in pair.addresses) {
        final icmp = <int?>[];
        final udp = <int?>[];
        final dot = <int?>[];
        for (final domain in queryDomains) {
          for (final measure in [
            () => probe.icmp(address, cancellation),
            () => probe.udpDns(address, domain, cancellation),
            () =>
                probe.dotDns(address, pair.tlsServerName, domain, cancellation),
          ].indexed) {
            cancellation.check();
            int? value;
            try {
              value = await measure.$2();
            } on DnsDiagnosticCancelled {
              rethrow;
            } catch (_) {
              // A failed individual measurement is recorded as loss.
            }
            cancellation.check();
            [
              icmp,
              udp,
              dot,
            ][measure.$1].add(value != null && value >= 0 ? value : null);
            onProgress(
              DnsDiagnosticProgress(
                ++completed,
                measurements,
                address,
                results,
              ),
            );
          }
        }
        endpoints.add(DnsEndpointResult(address, icmp, udp, dot));
      }
      results.add(DnsPairResult(pair, endpoints[0], endpoints[1]));
      onProgress(
        DnsDiagnosticProgress(completed, measurements, pair.secondary, results),
      );
    }
    cancellation.check();
    final eligible = results.where((result) => result.reliable).toList()
      ..sort((a, b) {
        final reliable = b.dnsSuccesses.compareTo(a.dnsSuccesses);
        if (reliable != 0) return reliable;
        final latency = a.latency.compareTo(b.latency);
        if (latency != 0) return latency;
        final echoes = b.icmpSuccesses.compareTo(a.icmpSuccesses);
        if (echoes != 0) return echoes;
        return diagnosticDnsPairs
            .indexOf(a.pair)
            .compareTo(diagnosticDnsPairs.indexOf(b.pair));
      });
    return DnsDiagnosticReport(results, eligible.firstOrNull);
  }
}
