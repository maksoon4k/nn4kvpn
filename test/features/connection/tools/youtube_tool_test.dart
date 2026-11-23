import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/features/connection/tools/youtube_tool.dart';
import 'package:flux/widgets/port_ui/port_ui.dart';

import '../../../support/tool_host.dart';

void main() {
  test('home, real video links and search point to HTTPS YouTube', () {
    expect(youtubeAddress(''), Uri.https('www.youtube.com', '/'));
    expect(
      youtubeAddress(
        '  VPN без рекламы & звук  ',
      ).queryParameters['search_query'],
      'VPN без рекламы & звук',
    );
    for (final address in [
      'https://www.youtube.com/watch?v=demo',
      'https://youtu.be/demo',
      'youtube.com/shorts/demo',
      'music.youtube.com/watch?v=demo',
      'https://m.youtube.com/',
    ]) {
      final uri = youtubeAddress(address);
      expect(uri.scheme, 'https');
      expect(uri.host == 'youtu.be' || uri.host.endsWith('youtube.com'), true);
    }
  });

  for (final bad in [
    'http://www.youtube.com/watch?v=x',
    'file:///D:/app.exe',
    'javascript:alert(1)',
    'https://youtube.com.evil.invalid/',
    'https://youtube.com@evil.invalid/',
    'https://evil.invalid/',
    'https://youtube.com:8443/',
    'https://youtube.com\\@evil.invalid/',
    'https://youtube.com/\nstart app.exe',
  ]) {
    test(
      'rejects unsafe or non-YouTube address $bad',
      () => expect(() => youtubeAddress(bad), throwsFormatException),
    );
  }
  test(
    'huge requests cannot be passed to ShellExecute',
    () => expect(() => youtubeAddress('x' * 8193), throwsFormatException),
  );

  testWidgets(
    'real browser opening is injected, searches submit and malformed links never reach the opener',
    (tester) async {
      final addresses = <Uri>[];
      await tester.pumpWidget(
        toolHost(
          YoutubeTool(
            openBrowser: (uri) async {
              addresses.add(uri);
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(addresses, [Uri.https('www.youtube.com', '/')]);
      await tester.enterText(
        find.byKey(const ValueKey('youtube-address')),
        'кот тестирует VPN',
      );
      await tapToolKey(tester, 'youtube-open');
      expect(
        addresses.last.queryParameters['search_query'],
        'кот тестирует VPN',
      );
      await tester.enterText(
        find.byKey(const ValueKey('youtube-address')),
        'https://youtu.be/demo',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(addresses.last.toString(), 'https://youtu.be/demo');
      final count = addresses.length;
      await tester.enterText(
        find.byKey(const ValueKey('youtube-address')),
        'https://evil.invalid/',
      );
      await tapToolKey(tester, 'youtube-open');
      expect(addresses.length, count);
      expect(find.textContaining('Разрешены только HTTPS'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'failed opening offers manual copy rather than claiming video playback',
    (tester) async {
      final clipboard = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        toolHost(YoutubeTool(openBrowser: (_) async => false)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Браузер не открылся'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('youtube-address')),
        'https://youtu.be/demo',
      );
      await tapToolKey(tester, 'youtube-copy');
      expect(clipboard, ['https://youtu.be/demo']);
      expect(find.text('Ссылка скопирована.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'opening is serialized and a late browser result cannot update a closed tool',
    (tester) async {
      final hold = Completer<bool>();
      var calls = 0;
      await tester.pumpWidget(
        toolHost(
          YoutubeTool(
            openBrowser: (_) {
              calls++;
              return hold.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        tester
            .widget<PortButton>(find.byKey(const ValueKey('youtube-open')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      hold.complete(true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
