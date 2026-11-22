import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Локальный loopback-порт, используемый только как IPC между экземплярами
/// Flux — выбран произвольно, но должен быть один и тот же в каждой сборке
/// (запись в реестр под `flux://` подразумевает, что ОС может запустить
/// второй процесс в любой момент, пока первый уже открыт).
const _singleInstancePort = 47812;
const maxSingleInstanceMessageBytes = 32 * 1024;
const maxSingleInstanceConnections = 8;

/// Результат попытки стать основным экземпляром приложения.
sealed class SingleInstanceResult {
  const SingleInstanceResult();
}

/// Этот процесс — единственный: держит слушателя порта и стрим диплинков,
/// присланных последующими (тут же завершающимися) запусками.
class PrimaryInstance extends SingleInstanceResult {
  final Stream<String> incomingDeepLinks;
  final int port;
  final Future<void> Function() _close;

  const PrimaryInstance._(this.incomingDeepLinks, this.port, this._close);

  /// Releases the listener and all in-flight messages. Idempotent.
  Future<void> close() => _close();
}

/// Уже есть работающий экземпляр — этот процесс переслал ему диплинк (если
/// он был) и должен немедленно завершиться без инициализации Flutter UI.
class SecondaryInstance extends SingleInstanceResult {
  const SecondaryInstance();
}

/// Пытается занять единственный на приложение loopback-порт. Успех —
/// значит, мы первый (и единственный) экземпляр Flux, нужно продолжать
/// обычный запуск. Если порт занят — где-то уже работает другой экземпляр:
/// шлём ему диплинк (если он есть в [deepLink]) через тот же порт и
/// возвращаем [SecondaryInstance], чтобы вызывающий код тут же вызвал
/// `exit(0)`, не создавая второе окно.
Future<SingleInstanceResult> acquireSingleInstance({
  String? deepLink,
  int port = _singleInstancePort,
  Duration messageTimeout = const Duration(seconds: 2),
}) async {
  if (messageTimeout <= Duration.zero) {
    throw ArgumentError.value(messageTimeout, 'messageTimeout');
  }
  try {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    final controller = StreamController<String>.broadcast();
    final sockets = <Socket>{};
    final shutdown = <Socket, void Function()>{};
    Future<void>? closing;
    final rateWindow = Stopwatch()..start();
    var acceptedInWindow = 0;

    void handleSocket(Socket socket) {
      if (closing != null || sockets.length >= maxSingleInstanceConnections) {
        socket.destroy();
        return;
      }
      sockets.add(socket);
      final bytes = BytesBuilder(copy: false);
      StreamSubscription<Uint8List>? subscription;
      Timer? deadline;
      var finished = false;

      void finish() {
        if (finished) return;
        finished = true;
        deadline?.cancel();
        sockets.remove(socket);
        shutdown.remove(socket);
        unawaited(subscription?.cancel());
        socket.destroy();
      }

      shutdown[socket] = finish;
      // A fixed deadline, not a resetting inactivity timeout: slow senders
      // cannot keep a connection alive forever by sending occasional bytes.
      deadline = Timer(messageTimeout, finish);
      subscription = socket.listen(
        (chunk) {
          final newline = chunk.indexOf(10);
          final length = newline < 0 ? chunk.length : newline;
          if (bytes.length + length > maxSingleInstanceMessageBytes) {
            finish();
            return;
          }
          bytes.add(
            newline < 0 ? chunk : Uint8List.sublistView(chunk, 0, newline),
          );
          if (newline < 0) return;
          try {
            final line = utf8
                .decode(bytes.takeBytes())
                .replaceFirst(RegExp(r'\r$'), '');
            if (line.isNotEmpty && !line.toLowerCase().startsWith('flux://')) {
              return;
            }
            if (rateWindow.elapsed >= const Duration(seconds: 10)) {
              rateWindow.reset();
              acceptedInWindow = 0;
            }
            if (++acceptedInWindow <= 8 && !controller.isClosed) {
              // Empty messages focus an already running application, too.
              controller.add(line);
            }
          } on FormatException {
            // Invalid UTF-8 from a local peer is not an application error.
          } finally {
            // Exactly one line per connection; never create an unbounded
            // LineSplitter buffer or open a dialog for every line of a flood.
            finish();
          }
        },
        onError: (Object _) => finish(),
        onDone: finish,
        cancelOnError: true,
      );
    }

    final listener = server.listen(handleSocket, onError: (Object _) {});
    Future<void> closeResources() async {
      for (final finish in shutdown.values.toList()) {
        finish();
      }
      await listener.cancel();
      await server.close();
      await controller.close();
    }

    return PrimaryInstance._(
      controller.stream,
      server.port,
      () => closing ??= closeResources(),
    );
  } on SocketException {
    // Порт занят — уже есть основной экземпляр. Передаём ему диплинк и
    // выходим.
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 2),
      );
      try {
        final message = deepLink ?? '';
        if (!message.contains('\n') &&
            !message.contains('\r') &&
            utf8.encode(message).length <= maxSingleInstanceMessageBytes) {
          socket.write('$message\n');
          await socket.flush().timeout(messageTimeout);
        }
      } finally {
        socket.destroy();
      }
    } catch (_) {
      // Основной экземпляр не ответил (завис/закрывается) — всё равно не
      // открываем второе окно, просто молча выходим.
    }
    return const SecondaryInstance();
  }
}
