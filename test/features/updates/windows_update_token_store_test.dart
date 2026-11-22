import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux/features/updates/github_release.dart';
import 'package:flux/features/updates/windows_update_token_store.dart';

void main() {
  test(
    'round-trips only a uniquely named test credential in Windows',
    () async {
      final store = WindowsUpdateTokenStore(
        targetPrefix: 'NN4K-Test/${DateTime.now().microsecondsSinceEpoch}',
      );
      const repository = 'owner/fixture';
      addTearDown(() => store.delete(repository));
      expect(await store.read(repository), isNull);
      await store.write(repository, 'test_not_a_real_github_token');
      expect(await store.read(repository), 'test_not_a_real_github_token');
      await store.delete(repository);
      expect(await store.read(repository), isNull);
      await store.delete(repository); // Missing credentials are not an error.
    },
    skip: !Platform.isWindows,
  );

  test('rejects empty, huge and control-character tokens', () async {
    final store = WindowsUpdateTokenStore(
      targetPrefix: 'NN4K-Test/${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(() => store.delete('owner/fixture'));
    for (final token in [
      '',
      'x' * 2561,
      'token\r\nInjected: header',
      'token with space',
    ]) {
      await expectLater(
        store.write('owner/fixture', token),
        throwsA(
          isA<UpdateException>().having(
            (error) => error.failure,
            'failure',
            UpdateFailure.credentials,
          ),
        ),
      );
    }
  }, skip: !Platform.isWindows);
}
