import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux/app/safe_app_exit.dart';

void main() {
  test(
    'game loss waits for safe shutdown before window closure and shares repeated requests',
    () async {
      final events = <String>[];
      final hold = Completer<void>();
      final exit = SafeAppExit(
        prepare: () async {
          events.add('prepare');
          await hold.future;
          events.add('stopped');
        },
        cancel: () => events.add('cancel'),
        close: () async => events.add('close'),
      );
      final first = exit.exit();
      expect(identical(first, exit.exit()), true);
      expect(events, ['prepare']);
      hold.complete();
      await first;
      expect(events, ['prepare', 'stopped', 'close']);
    },
  );

  test(
    'failed stop never closes, unlocks reconnects and allows a later retry',
    () async {
      var fail = true;
      final events = <String>[];
      final exit = SafeAppExit(
        prepare: () async {
          events.add('prepare');
          if (fail) throw StateError('Fixture stop failure');
        },
        cancel: () => events.add('cancel'),
        close: () async => events.add('close'),
      );
      await expectLater(exit.exit(), throwsStateError);
      expect(events, ['prepare', 'cancel']);
      fail = false;
      await exit.exit();
      expect(events, ['prepare', 'cancel', 'prepare', 'close']);
    },
  );

  test(
    'failed window closure also unlocks the client without claiming success',
    () async {
      var cancelled = 0;
      final exit = SafeAppExit(
        prepare: () async {},
        cancel: () => cancelled++,
        close: () async => throw StateError('Fixture close failure'),
      );
      await expectLater(exit.exit(), throwsStateError);
      expect(cancelled, 1);
    },
  );
}
