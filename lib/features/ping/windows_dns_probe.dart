import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../app/windows_system_executable.dart';
import '../../core_abstraction/dns_resolver.dart';
import '../../engines/xray/child_process_job.dart';
import 'dns_diagnostic_service.dart';
import 'dns_wire.dart';

class WindowsDnsProbe implements DnsDiagnosticProbe {
  const WindowsDnsProbe();
  static const dnsTimeout = Duration(seconds: 2);

  static InternetAddress _literal(String address) {
    // Never accept an arbitrary host/argument from settings or a subscription.
    if (!diagnosticDnsPairs.any((pair) => pair.addresses.contains(address))) {
      throw const FormatException('Unknown diagnostic resolver');
    }
    return InternetAddress(address, type: InternetAddressType.IPv4);
  }

  static int? parseWindowsEcho(String output, int exitCode) {
    if (exitCode != 0) return null;
    // TTL and ASCII separators survive every Windows console codepage. This
    // also accepts Russian "мс" and "время<1мс" without guessing its encoding.
    final match = RegExp(
      r'[=<]\s*(\d+)[^=<\r\n]*\bTTL=',
      caseSensitive: false,
    ).firstMatch(output);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  @override
  Future<int?> icmp(
    String address,
    DnsDiagnosticCancellation cancellation,
  ) async {
    _literal(address);
    cancellation.check();
    if (!Platform.isWindows) return null;
    Process? process;
    void Function()? unregister;
    try {
      process = await Process.start(windowsSystemExecutable('ping.exe'), [
        '-4',
        '-n',
        '1',
        '-w',
        '750',
        address,
      ]);
      final running = process;
      unregister = cancellation.onCancel(() => running.kill());
      tieChildProcessLifetimeToApp(running);
      final output = <int>[];
      final stdout = running.stdout.forEach((chunk) {
        if (output.length + chunk.length > 8192) {
          running.kill();
        } else {
          output.addAll(chunk);
        }
      });
      final stderr = running.stderr.drain<void>();
      final result = await Future.wait<Object?>([
        running.exitCode,
        stdout,
        stderr,
      ]).timeout(const Duration(seconds: 3));
      cancellation.check();
      return parseWindowsEcho(latin1.decode(output), result[0] as int);
    } on DnsDiagnosticCancelled {
      rethrow;
    } catch (_) {
      cancellation.check();
      return null;
    } finally {
      unregister?.call();
      process?.kill();
    }
  }

  @override
  Future<int?> udpDns(
    String address,
    String domain,
    DnsDiagnosticCancellation cancellation,
  ) async {
    final target = _literal(address);
    cancellation.check();
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    void Function()? unregister;
    final watch = Stopwatch()..start();
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final active = socket;
      final reply = Completer<bool>();
      final id = Random.secure().nextInt(65536);
      final query = DnsWire.query(domain, id);
      var receivedPackets = 0;
      unregister = cancellation.onCancel(() {
        active.close();
        if (!reply.isCompleted) reply.complete(false);
      });
      cancellation.check();
      subscription = active.listen(
        (event) {
          if (event != RawSocketEvent.read || reply.isCompleted) return;
          Datagram? packet;
          while ((packet = active.receive()) != null) {
            final current = packet!;
            if (++receivedPackets > 64) {
              reply.complete(false);
              active.close();
              return;
            }
            if (current.address.address == target.address &&
                current.port == 53 &&
                DnsWire.isUsableAnswer(current.data, domain, id)) {
              reply.complete(true);
              return;
            }
          }
        },
        onError: (Object _) {
          if (!reply.isCompleted) reply.complete(false);
        },
        onDone: () {
          if (!reply.isCompleted) reply.complete(false);
        },
      );
      if (active.send(query, target, 53) != query.length) return null;
      final valid = await reply.future.timeout(dnsTimeout);
      cancellation.check();
      return valid ? watch.elapsedMilliseconds : null;
    } on DnsDiagnosticCancelled {
      rethrow;
    } catch (_) {
      cancellation.check();
      return null;
    } finally {
      unregister?.call();
      await subscription?.cancel();
      socket?.close();
    }
  }

  @override
  Future<int?> dotDns(
    String address,
    String? serverName,
    String domain,
    DnsDiagnosticCancellation cancellation,
  ) async {
    final target = _literal(address);
    if (serverName != dnsTlsServerNameFor(address)) {
      throw const FormatException('Unknown diagnostic TLS identity');
    }
    cancellation.check();
    Socket? raw;
    ConnectionTask<Socket>? task;
    SecureSocket? secure;
    StreamSubscription<Uint8List>? subscription;
    void Function()? unregister;
    var acceptingSocket = true;
    final watch = Stopwatch()..start();
    Duration remaining() {
      final budget = dnsTimeout - watch.elapsed;
      if (budget <= Duration.zero) throw TimeoutException('DNS probe timeout');
      return budget;
    }

    try {
      task = await Socket.startConnect(target, 853);
      unregister = cancellation.onCancel(task.cancel);
      raw = await task.socket.timeout(remaining());
      unregister();
      final connected = raw;
      unregister = cancellation.onCancel(connected.destroy);
      cancellation.check();
      final handshake =
          SecureSocket.secure(
            connected,
            host: serverName ?? address,
            // Default trust/certificate checks stay enabled. Never accept a bad
            // certificate just to turn an unreachable resolver into a winner.
          ).then((socket) {
            // Future.timeout does not cancel its source. A successful handshake
            // arriving after timeout/cancellation must not leak a detached socket.
            if (!acceptingSocket || cancellation.cancelled) socket.destroy();
            return socket;
          });
      secure = await handshake.timeout(remaining());
      unregister();
      final active = secure;
      final reply = Completer<bool>();
      unregister = cancellation.onCancel(() {
        active.destroy();
        if (!reply.isCompleted) reply.complete(false);
      });
      cancellation.check();
      final id = Random.secure().nextInt(65536);
      final query = DnsWire.query(domain, id);
      final reader = DnsTcpAnswerReader(domain, id);
      subscription = active.listen(
        (chunk) {
          if (reply.isCompleted) return;
          final valid = reader.add(chunk);
          if (valid != null) reply.complete(valid);
        },
        onError: (Object _) {
          if (!reply.isCompleted) reply.complete(false);
        },
        onDone: () {
          if (!reply.isCompleted) reply.complete(false);
        },
      );
      active.add([query.length >> 8, query.length & 255, ...query]);
      await active.flush().timeout(remaining());
      final valid = await reply.future.timeout(remaining());
      cancellation.check();
      return valid ? watch.elapsedMilliseconds : null;
    } on DnsDiagnosticCancelled {
      rethrow;
    } catch (_) {
      cancellation.check();
      return null;
    } finally {
      acceptingSocket = false;
      unregister?.call();
      await subscription?.cancel();
      secure?.destroy();
      raw?.destroy();
      task?.cancel();
    }
  }
}
