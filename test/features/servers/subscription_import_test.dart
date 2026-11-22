import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux/core_abstraction/proxy_node.dart';
import 'package:flux/core_abstraction/server_config.dart';
import 'package:flux/core_abstraction/subscription.dart';
import 'package:flux/features/servers/subscription_import.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _variant = ConnectionVariant(
  id: 'v1',
  label: 'TCP Reality',
  config: VlessConfig(address: 'de1.example.com', port: 443, uuid: 'u1'),
);
const _leaf = ServerLeaf(
  id: 'leaf1',
  name: 'Germany 1',
  variants: [_variant],
  selection: ManualVariantSelection('v1'),
);

Subscription _baseSubscription({
  required String url,
  List<String> fallbackDomains = const [],
  String? fallbackDomainsUrl,
  int domainTimeoutMs = 200,
}) => Subscription(
  id: 'sub1',
  name: 'Sub',
  url: url,
  fallbackDomains: fallbackDomains,
  fallbackDomainsUrl: fallbackDomainsUrl,
  domainTimeoutMs: domainTimeoutMs,
  root: const ServerGroup(id: 'root', name: 'Sub', children: [_leaf]),
);

String _mjBody(Subscription subscription) => jsonEncode({
  'schemaVersion': 1,
  'type': 'subscriptions',
  'content': [subscription.toJson()],
});

void main() {
  group('untrusted subscription response limits', () {
    test(
      'rejects an oversized body instead of parsing it or trying fallback hosts',
      () async {
        final hosts = <String>[];
        final client = MockClient((request) async {
          hosts.add(request.url.host);
          return http.Response('a' * (maxSubscriptionBytes + 1), 200);
        });
        final result = await refreshSubscription(
          _baseSubscription(
            url: 'https://example.com/sub',
            fallbackDomains: ['other.example'],
          ),
          client: client,
        );
        expect(result, isA<LinkImportFailure>());
        expect(result, isNot(isA<DomainUnavailableFailure>()));
        expect(hosts, ['example.com']);
      },
    );

    test(
      'malformed Magic JSON returns a failure rather than a cast exception',
      () async {
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'type': 'subscriptions',
              'content': [42],
            }),
            200,
          ),
        );
        final result = await importLink(
          'https://example.com/sub',
          client: client,
        );
        expect(result, isA<LinkImportFailure>());
      },
    );

    test('out-of-range expiry headers cannot crash import', () async {
      final client = MockClient(
        (_) async => http.Response(
          'vless://test-id@example.com:443#Server',
          200,
          headers: {
            'subscription-userinfo':
                'upload=1; download=2; total=3; expire=9223372036854775807',
          },
        ),
      );
      final result = await importLink(
        'https://example.com/sub',
        client: client,
      );
      expect(result, isA<SubscriptionImportResultOk>());
      expect(
        (result as SubscriptionImportResultOk).subscription.expiresAt,
        isNull,
      );
    });

    test(
      'bounds the number of fallback attempts across large static lists',
      () async {
        final hosts = <String>[];
        final client = MockClient((request) async {
          hosts.add(request.url.host);
          throw const SocketException('unavailable');
        });
        final result = await refreshSubscription(
          _baseSubscription(
            url: 'https://example.com/sub',
            fallbackDomains: List.generate(100, (i) => 'mirror$i.example'),
            fallbackDomainsUrl: 'https://list.example/domains.json',
          ),
          client: client,
        );
        expect(result, isA<DomainUnavailableFailure>());
        expect(hosts, hasLength(1 + maxFallbackDomainAttempts));
        expect(hosts, isNot(contains('list.example')));
      },
    );

    test(
      'filters non-string and invalid fetched hosts and bounds the saved list',
      () async {
        final replacement = _baseSubscription(url: 'https://example.com/sub');
        final client = MockClient((request) async {
          if (request.url.host == 'example.com') {
            throw const SocketException('unavailable');
          }
          if (request.url.host == 'list.example') {
            return http.Response(
              jsonEncode({
                'domains': [
                  null,
                  42,
                  {'host': 'bad.example'},
                  'user@bad.example',
                  'https://bad.example',
                  '-bad.example',
                  ...List.generate(100, (i) => 'mirror$i.example'),
                ],
              }),
              200,
            );
          }
          return http.Response(_mjBody(replacement), 200);
        });
        final result = await refreshSubscription(
          _baseSubscription(
            url: 'https://example.com/sub',
            fallbackDomainsUrl: 'https://list.example/domains.json',
          ),
          client: client,
        );
        expect(result, isA<SubscriptionImportResultOk>());
        final subscription =
            (result as SubscriptionImportResultOk).subscription;
        expect(subscription.url, 'https://mirror0.example/sub');
        expect(
          subscription.fallbackDomains,
          hasLength(maxFallbackDomainAttempts),
        );
      },
    );

    test('clamps invalid remote timeouts to a positive lower bound', () async {
      final replacement = _baseSubscription(url: 'https://example.com/sub');
      final client = MockClient(
        (_) async => http.Response(_mjBody(replacement), 200),
      );
      final result = await refreshSubscription(
        _baseSubscription(url: 'https://example.com/sub', domainTimeoutMs: -1),
        client: client,
      );
      expect(result, isA<SubscriptionImportResultOk>());
    });
  });

  group('importLink domain-unavailable classification', () {
    test('SocketException becomes DomainUnavailableFailure', () async {
      final client = MockClient((request) async {
        throw const SocketException('connection refused');
      });

      final result = await importLink(
        'https://example.com/sub',
        client: client,
      );

      expect(result, isA<DomainUnavailableFailure>());
    });

    test(
      'a slow response past the timeout becomes DomainUnavailableFailure',
      () async {
        final client = MockClient((request) async {
          await Future.delayed(const Duration(milliseconds: 300));
          return http.Response('{}', 200);
        });

        final result = await importLink(
          'https://example.com/sub',
          client: client,
          timeout: const Duration(milliseconds: 50),
        );

        expect(result, isA<DomainUnavailableFailure>());
      },
    );

    test(
      'a real 5xx from a live server is a plain LinkImportFailure, not domain-unavailable',
      () async {
        final client = MockClient(
          (request) async => http.Response('error', 503),
        );

        final result = await importLink(
          'https://example.com/sub',
          client: client,
        );

        expect(result, isA<LinkImportFailure>());
        expect(result, isNot(isA<DomainUnavailableFailure>()));
      },
    );
  });

  group('refreshSubscription fallback domains (ROADMAP.md, трек 23)', () {
    test(
      'falls back to the next static domain when the primary domain is unavailable',
      () async {
        final replacement = _baseSubscription(
          url: 'https://example.com/sub/id1',
        );
        final client = MockClient((request) async {
          if (request.url.host == 'example.com') {
            throw const SocketException('name not resolved');
          }
          if (request.url.host == 'example2.com') {
            return http.Response(_mjBody(replacement), 200);
          }
          throw StateError('unexpected host ${request.url.host}');
        });

        final subscription = _baseSubscription(
          url: 'https://example.com/sub/id1',
          fallbackDomains: const ['example2.com'],
        );

        final result = await refreshSubscription(subscription, client: client);

        expect(result, isA<SubscriptionImportResultOk>());
        final merged = (result as SubscriptionImportResultOk).subscription;
        // Путь/query сохранены, поменялся только хост.
        expect(merged.url, 'https://example2.com/sub/id1');
      },
    );

    test(
      'fetches the fallback domains URL once the static list is exhausted, and replaces it',
      () async {
        final replacement = _baseSubscription(
          url: 'https://example.com/sub/id1',
        );
        final client = MockClient((request) async {
          if (request.url.host == 'example.com' &&
              request.url.path == '/sub/id1') {
            throw const SocketException('name not resolved');
          }
          if (request.url.host == 'dead-fallback.example') {
            throw const SocketException('name not resolved');
          }
          if (request.url.toString() == 'https://raw.example/domains.json') {
            return http.Response(
              jsonEncode({
                'domains': ['example3.com'],
              }),
              200,
            );
          }
          if (request.url.host == 'example3.com') {
            return http.Response(_mjBody(replacement), 200);
          }
          throw StateError('unexpected request ${request.url}');
        });

        final subscription = _baseSubscription(
          url: 'https://example.com/sub/id1',
          fallbackDomains: const ['dead-fallback.example'],
          fallbackDomainsUrl: 'https://raw.example/domains.json',
        );

        final result = await refreshSubscription(subscription, client: client);

        expect(result, isA<SubscriptionImportResultOk>());
        final merged = (result as SubscriptionImportResultOk).subscription;
        expect(merged.url, 'https://example3.com/sub/id1');
        // Статический список заменён результатом JSON-фетча этого раунда.
        expect(merged.fallbackDomains, ['example3.com']);
      },
    );

    test(
      'does not attempt any fallback when the primary domain returns a real HTTP error',
      () async {
        var fallbackHostRequested = false;
        final client = MockClient((request) async {
          if (request.url.host == 'example.com') {
            return http.Response('server error', 500);
          }
          fallbackHostRequested = true;
          throw StateError('should not be called');
        });

        final subscription = _baseSubscription(
          url: 'https://example.com/sub/id1',
          fallbackDomains: const ['example2.com'],
        );

        final result = await refreshSubscription(subscription, client: client);

        expect(fallbackHostRequested, isFalse);
        expect(result, isA<LinkImportFailure>());
        expect(result, isNot(isA<DomainUnavailableFailure>()));
      },
    );

    test(
      'with no fallback domains configured, a domain-unavailable failure is returned as-is',
      () async {
        final client = MockClient((request) async {
          throw const SocketException('name not resolved');
        });

        final subscription = _baseSubscription(
          url: 'https://example.com/sub/id1',
        );

        final result = await refreshSubscription(subscription, client: client);

        expect(result, isA<DomainUnavailableFailure>());
      },
    );
  });
}
