import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux/core_abstraction/atomic_json_file.dart';

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('nn4k-json-tests-'),
  );
  tearDown(() async => directory.delete(recursive: true));

  test(
    'replaces a complete JSON file and cleans its staging directory',
    () async {
      final file = File('${directory.path}/profile.json');
      writeJsonFileAtomically(file, '{"value":1}');
      writeJsonFileAtomically(file, '{"value":2}');
      expect(jsonDecode(await file.readAsString()), {'value': 2});
      expect((await directory.list().toList()).length, 1);
    },
  );

  test('a failed rename leaves an existing target untouched', () async {
    final target = await Directory('${directory.path}/existing').create();
    final keep = await File('${target.path}/user-data.txt')
        .writeAsString('keep');
    expect(
      () => writeJsonFileAtomically(File(target.path), '{}'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await keep.readAsString(), 'keep');
    expect((await directory.list().toList()).length, 1);
  });
}
