import 'package:flutter_test/flutter_test.dart';
import 'package:flux/app/deep_link.dart';

void main() {
  group('parseFluxDeepLink', () {
    for (final payload in [
      'vless://test-id@example.test:443#Сервер',
      'hysteria2://secret@example.test:443',
      'hy2://secret@example.test:443',
      'https://example.test/sub?token=private&format=json',
      'http://example.test/sub',
    ]) {
      test(
        'decodes an encoded path or query exactly once: ${Uri.parse(payload).scheme}',
        () {
          final encoded = Uri.encodeComponent(payload);
          expect(parseFluxDeepLink('flux://add/$encoded'), payload);
          expect(parseFluxDeepLink('FLUX://ADD?url=$encoded'), payload);
        },
      );
    }

    test('accepts a plain supported path without doing an import', () {
      expect(
        parseFluxDeepLink('flux://add/https://example.test/sub'),
        'https://example.test/sub',
      );
    });

    for (final raw in [
      '',
      'https://example.test/sub',
      'flux://connect/https://example.test/sub',
      'flux://updates?url=https%3A%2F%2Fexample.test',
      'flux://user@add/https://example.test/sub',
      'flux://add:123/https://example.test/sub',
      'flux://add',
      'flux://add?url=',
      'flux://add?url=https%3A%2F%2Fone.test&url=https%3A%2F%2Ftwo.test',
      'flux://add?url=%FF',
      'flux://add/%FF',
      'flux://add?url=%',
      'flux://add/%ZZ',
      'flux://add?url=https%3A%2F%2Fexample.test%00secret',
      'flux://add?url=https%3A%2F%2Fexample.test%0Asecret',
      'flux://add/https://example.test/sub\n',
      'flux://add/file%3A%2F%2FC%3A%2Fprivate.txt',
      'flux://add/javascript%3Aalert(1)',
      'flux://add/powershell%3Aanything',
    ]) {
      test('ignores malformed or unsupported input without throwing: $raw', () {
        expect(parseFluxDeepLink(raw), isNull);
      });
    }

    test('bounds command-line input as well as IPC input', () {
      expect(
        parseFluxDeepLink('flux://add/${'a' * maxFluxDeepLinkLength}'),
        isNull,
      );
    });

    test('does not turn a double-encoded value into an active link', () {
      final encoded = Uri.encodeComponent(
        Uri.encodeComponent('https://example.test/sub'),
      );
      expect(parseFluxDeepLink('flux://add/$encoded'), isNull);
    });
  });

  test('extracts the first bounded protocol argument without executing it', () {
    expect(
      extractFluxDeepLinkFromArgs([
        '--minimized',
        'FLUX://add/https://example.test/sub',
      ]),
      'FLUX://add/https://example.test/sub',
    );
    expect(
      extractFluxDeepLinkFromArgs(['--safe-start', 'https://example.test/sub']),
      isNull,
    );
    expect(
      extractFluxDeepLinkFromArgs([
        'flux://add/${'a' * maxFluxDeepLinkLength}',
      ]),
      isNull,
    );
  });
}
