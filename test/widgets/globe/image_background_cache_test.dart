import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/features/settings/managed_background_storage.dart';

Future<Uint8List> png(ui.Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 2, 2),
    ui.Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(2, 2);
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

Future<List<int>> pixel(FileImage provider) async {
  final stream = provider.resolve(ImageConfiguration.empty);
  final complete = Completer<ImageInfo>();
  final listener = ImageStreamListener(
    (image, _) => complete.complete(image),
    onError: complete.completeError,
  );
  stream.addListener(listener);
  final image = await complete.future;
  try {
    final bytes = (await image.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    return bytes.buffer.asUint8List().sublist(0, 4);
  } finally {
    stream.removeListener(listener);
    image.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'same-extension replacement bypasses the old decoded FileImage cache without global cache clearing',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nn4k-image-cache-test-',
      );
      final storage = ManagedBackgroundStorage(
        Directory('${directory.path}/owned'),
        prefix: 'custom_background',
      );
      final source = File('${directory.path}/image.png');
      FileImage? old;
      FileImage? next;
      try {
        await source.writeAsBytes(await png(const ui.Color(0xFFFF0000)));
        final firstPath = await storage.import(source.path);
        old = FileImage(File(firstPath));
        expect(await pixel(old), [255, 0, 0, 255]);
        await source.writeAsBytes(await png(const ui.Color(0xFF0000FF)));
        final secondPath = await storage.import(source.path);
        next = FileImage(File(secondPath));
        expect(
          await old.obtainKey(ImageConfiguration.empty),
          isNot(await next.obtainKey(ImageConfiguration.empty)),
        );
        expect(await pixel(next), [0, 0, 255, 255]);
        expect(await pixel(old), [255, 0, 0, 255]);
        await storage.delete(firstPath);
        expect(await pixel(next), [0, 0, 255, 255]);
      } finally {
        await old?.evict();
        await next?.evict();
        await directory.delete(recursive: true);
      }
    },
  );
}
