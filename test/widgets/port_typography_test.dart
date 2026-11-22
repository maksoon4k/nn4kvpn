import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/widgets/port_ui/port_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fontPins = <String, (int, String)>{
    'Inter-Regular.ttf': (
      324796,
      '15b294b67f2f8bbc04d990023ef4aec66502b87dc9040d84abe5f896ccb693de',
    ),
    'Inter-Medium.ttf': (
      325280,
      '36a36ff7ac46dc2aeceac3a80a87a67e7b844b8fc936699259aac8fba9bcf734',
    ),
    'Inter-SemiBold.ttf': (
      326024,
      '334bb2c51aeba5f566abac8d03a7e75ab3234d6926b52e92a85dc704129258b5',
    ),
  };

  test('original typography metrics and Inter weights are retained', () {
    final styles = [
      PortText.h4,
      PortText.large,
      PortText.p,
      PortText.small,
      PortText.muted,
    ];
    expect(styles.map((style) => style.fontFamily), everyElement('Inter'));
    expect(styles.map((style) => style.fontSize), [20, 18, 16, 14, 14]);
    expect(styles.map((style) => style.fontWeight), [
      FontWeight.w600,
      FontWeight.w600,
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w400,
    ]);
    expect(PortText.h4.letterSpacing, -0.4);
    expect(PortText.p.height, 28 / 16);
    expect(PortText.small.height, 1);
    expect(PortText.h4.color, PortColors.foreground);
    expect(PortText.muted.color, PortColors.mutedForeground);
  });

  for (final entry in fontPins.entries) {
    test('${entry.key} is bundled with the original byte/hash pin', () async {
      final data = await rootBundle.load('assets/fonts/${entry.key}');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      expect(data.getUint32(0), 0x00010000);
      expect(bytes.length, entry.value.$1);
      expect(sha256.convert(bytes).toString(), entry.value.$2);
    });
  }

  test('Flutter declares all three local Inter weights', () async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    final inter = manifest.cast<Map<String, dynamic>>().singleWhere(
      (font) => font['family'] == 'Inter',
    );
    expect(inter['fonts'], [
      {'asset': 'assets/fonts/Inter-Regular.ttf', 'weight': 400},
      {'asset': 'assets/fonts/Inter-Medium.ttf', 'weight': 500},
      {'asset': 'assets/fonts/Inter-SemiBold.ttf', 'weight': 600},
    ]);
  });

  test(
    'the Inter copyright and license are distributed as readable assets',
    () async {
      final license = await rootBundle.loadString('assets/fonts/OFL.txt');
      expect(license, contains('Copyright 2020 The Inter Project Authors'));
      expect(license, contains('SIL OPEN FONT LICENSE Version 1.1'));
      expect(license, contains('PERMISSION & CONDITIONS'));
    },
  );

  testWidgets('building all UI text styles creates no HTTP client', (
    tester,
  ) async {
    var httpClientCreations = 0;
    await HttpOverrides.runZoned(
      () async {
        await tester.pumpWidget(
          PortApp(
            home: Column(
              children: [
                Text('NN4K', style: PortText.h4),
                Text('Добро пожаловать', style: PortText.large),
                Text('Offline first run', style: PortText.p),
                Text('Первоначальная настройка', style: PortText.small),
                Text('Без загрузки шрифтов', style: PortText.muted),
              ],
            ),
          ),
        );
        await tester.pump();
      },
      createHttpClient: (_) {
        httpClientCreations++;
        throw StateError('UI typography must not initialize an HTTP client');
      },
    );
    expect(httpClientCreations, 0);
    expect(find.text('Добро пожаловать'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
