import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

const cassetteNames = ['Ночной маршрут', 'Шум шифрования', 'Лоу-фай пакеты'];
const cassetteSampleRate = 22050;
const cassetteSeconds = 16;

/// Original, deterministic PCM loops. No bundled music, downloads, microphone,
/// sound-device changes or codec libraries; only the selected loop is made.
Uint8List synthesizeCassette(int tape) {
  RangeError.checkValidIndex(tape, cassetteNames);
  const samples = cassetteSampleRate * cassetteSeconds;
  const dataLength = samples * 2; // mono signed 16-bit PCM
  final bytes = Uint8List(44 + dataLength);
  final data = ByteData.sublistView(bytes);
  void text(int offset, String value) =>
      bytes.setRange(offset, offset + value.length, value.codeUnits);
  text(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, cassetteSampleRate, Endian.little);
  data.setUint32(28, cassetteSampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, dataLength, Endian.little);

  final random = math.Random(7401 + tape);
  var filteredNoise = 0.0;
  const chords = [130.8128, 174.6141, 164.8138, 146.8324];
  const notes = [
    261.6256,
    329.6276,
    391.9954,
    329.6276,
    293.6648,
    349.2282,
    440.0,
    349.2282,
  ];
  double tone(double frequency, double time) =>
      math.sin(2 * math.pi * frequency * time);
  for (var i = 0; i < samples; i++) {
    final t = i / cassetteSampleRate;
    final beat = t % .5;
    final chord = chords[(t / 4).floor() % chords.length];
    final noise = random.nextDouble() * 2 - 1;
    filteredNoise = filteredNoise * .965 + noise * .035;
    double value;
    switch (tape) {
      case 0:
        final pulse = .7 + .3 * tone(.125, t);
        value =
            .20 *
                pulse *
                (tone(chord, t) +
                    .55 * tone(chord * 1.5, t) +
                    .3 * tone(chord * 2, t)) +
            filteredNoise * .1;
      case 1:
        value =
            .72 * filteredNoise +
            .035 * tone(110, t) +
            .10 * noise * math.exp(-beat * 36);
      default:
        final envelope = math.exp(-beat * 5) * math.min(1.0, beat * 80);
        final note = notes[(t * 2).floor() % notes.length];
        final kick =
            tone(53 + 40 * math.exp(-beat * 28), beat) * math.exp(-beat * 18);
        value =
            .18 * envelope * tone(note, t) +
            .15 * kick +
            .045 * tone(chord / 2, t) +
            .055 * noise * math.exp(-beat * 45);
    }
    // Short fades avoid pops on first play, rewind and loop boundaries.
    final fade = math
        .min(
          1.0,
          math.min(
            t / .04,
            (cassetteSeconds - 1 / cassetteSampleRate - t) / .04,
          ),
        )
        .clamp(0.0, 1.0);
    data.setInt16(
      44 + i * 2,
      (value * fade * 32767).round().clamp(-24000, 24000),
      Endian.little,
    );
  }
  return bytes;
}

abstract class CassetteAudioSource {
  Future<String> prepare(int tape);
  Future<void> dispose();
}

/// Each tool owns a new private temporary directory. User-selected files are
/// never copied or removed. Cleanup waits for its exact preparation jobs.
class TemporaryCassetteAudioSource implements CassetteAudioSource {
  final Directory? parent;
  Future<Directory>? _directory;
  final _preparations = <int, Future<String>>{};
  bool _disposed = false;
  Future<void>? _cleanup;

  TemporaryCassetteAudioSource({this.parent});

  @override
  Future<String> prepare(int tape) {
    RangeError.checkValidIndex(tape, cassetteNames);
    if (_disposed) return Future.error(StateError('Cassette source is closed'));
    return _preparations.putIfAbsent(tape, () => _prepare(tape));
  }

  Future<String> _prepare(int tape) async {
    final directory = await (_directory ??= (parent ?? Directory.systemTemp)
        .createTemp('nn4k-cassette-'));
    final bytes = await Isolate.run(() => synthesizeCassette(tape));
    final file = File('${directory.path}/tape-$tape.wav');
    await file.writeAsBytes(bytes, flush: true);
    if (_disposed) throw StateError('Cassette source is closed');
    return file.path;
  }

  @override
  Future<void> dispose() {
    _disposed = true;
    return _cleanup ??= _removeOwnedFiles();
  }

  Future<void> _removeOwnedFiles() async {
    for (final job in _preparations.values.toList()) {
      try {
        await job;
      } catch (_) {
        /* A failed preparation still needs cleanup. */
      }
    }
    final creating = _directory;
    if (creating == null) return;
    try {
      final directory = await creating;
      for (var tape = 0; tape < cassetteNames.length; tape++) {
        final file = File('${directory.path}/tape-$tape.wav');
        if (await file.exists()) await file.delete();
      }
      await directory.delete();
    } on FileSystemException {
      // A failed native decoder release may retain a lock. Do not touch files
      // outside this one private directory or turn closing the tool into a crash.
    }
  }
}
