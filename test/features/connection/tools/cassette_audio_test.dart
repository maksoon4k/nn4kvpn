import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux/features/connection/tools/cassette_audio.dart';

void main() {
  for (var tape = 0; tape < cassetteNames.length; tape++) {
    test('cassette $tape is audible bounded original PCM, not a UI timer', () {
      final bytes = synthesizeCassette(tape);
      final data = ByteData.sublistView(bytes);
      String text(int start, int count) =>
          String.fromCharCodes(bytes.sublist(start, start + count));
      expect(text(0, 4), 'RIFF');
      expect(text(8, 4), 'WAVE');
      expect(text(12, 4), 'fmt ');
      expect(text(36, 4), 'data');
      expect(data.getUint32(4, Endian.little), bytes.length - 8);
      expect(data.getUint16(20, Endian.little), 1);
      expect(data.getUint16(22, Endian.little), 1);
      expect(data.getUint32(24, Endian.little), cassetteSampleRate);
      expect(data.getUint16(34, Endian.little), 16);
      expect(
        data.getUint32(40, Endian.little),
        cassetteSampleRate * cassetteSeconds * 2,
      );
      expect(bytes.length, lessThan(1024 * 1024));
      var loudest = 0;
      var nonzero = 0;
      for (var offset = 44; offset < bytes.length; offset += 2) {
        final sample = data.getInt16(offset, Endian.little).abs();
        if (sample > loudest) loudest = sample;
        if (sample > 128) nonzero++;
      }
      expect(loudest, inInclusiveRange(2000, 24000));
      expect(nonzero, greaterThan(cassetteSampleRate));
      expect(data.getInt16(44, Endian.little), 0);
      expect(data.getInt16(bytes.length - 2, Endian.little), 0);
      expect(synthesizeCassette(tape), bytes);
    });
  }

  test('tracks differ and do not accept unbounded input', () {
    expect(synthesizeCassette(0), isNot(synthesizeCassette(1)));
    expect(synthesizeCassette(1), isNot(synthesizeCassette(2)));
    expect(() => synthesizeCassette(-1), throwsRangeError);
    expect(() => synthesizeCassette(3), throwsRangeError);
  });

  test(
    'selected tracks share preparation, and cleanup owns only its new directory',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'nn4k-cassette-source-test-',
      );
      final unrelated = await File(
        '${parent.path}/keep.wav',
      ).writeAsString('user fixture');
      final source = TemporaryCassetteAudioSource(parent: parent);
      try {
        final first = source.prepare(0);
        expect(identical(first, source.prepare(0)), true);
        final path = await first;
        expect(await File(path).readAsBytes(), synthesizeCassette(0));
        expect((await File(path).parent.list().toList()).length, 1);
        await source.dispose();
        await source.dispose();
        expect(await File(path).exists(), false);
        expect(await unrelated.readAsString(), 'user fixture');
        await expectLater(source.prepare(1), throwsStateError);
      } finally {
        await parent.delete(recursive: true);
      }
    },
  );

  test(
    'closing during preparation never recreates a deleted audio directory',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'nn4k-cassette-obsolete-test-',
      );
      final source = TemporaryCassetteAudioSource(parent: parent);
      final pending = source.prepare(2);
      final rejected = expectLater(pending, throwsStateError);
      await source.dispose();
      await rejected;
      expect(await parent.list().toList(), isEmpty);
      await parent.delete();
    },
  );
}
