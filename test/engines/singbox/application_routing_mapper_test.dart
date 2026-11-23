import 'package:flutter_test/flutter_test.dart';
import 'package:flux/core_abstraction/tun_application_routing.dart';
import 'package:flux/core_abstraction/proxy_node.dart';
import 'package:flux/engines/singbox/singbox_config_mapper.dart';

Map<String, dynamic> configuration(TunApplicationRouting policy) =>
    buildSingBoxTunBridgeConfig(
      socksInPort: 10808,
      serverHost: 'fixture.invalid',
      serverIps: const ['203.0.113.7'],
      applicationRouting: policy,
      routingRules: const [
        DomainRule(values: ['domain:example.net'], outboundTag: 'block'),
      ],
      defaultOutboundTag: 'block',
    );

void main() {
  test('disabled routing is identical to existing domain/IP behavior', () {
    final config = configuration(const TunApplicationRouting());
    final route = config['route'] as Map;
    expect(route['final'], 'block');
    expect(route.containsKey('find_process'), false);
    expect(
      (route['rules'] as List).any(
        (r) => (r as Map).containsKey('process_path_regex'),
      ),
      false,
    );
  });

  for (final mode in TunApplicationRoutingMode.values) {
    test(
      '$mode uses explicit fallback and real direct/proxy/reject matches',
      () {
        final policy = TunApplicationRouting.fromJson({
          'enabled': true,
          'mode': mode.name,
          'rules': [
            {'processName': 'same.exe', 'action': 'proxy'},
            {'processPath': r'D:\Apps (portable)\same.exe', 'action': 'block'},
            {'processName': 'direct.exe', 'action': 'direct'},
            {
              'processName': 'disabled.exe',
              'action': 'block',
              'enabled': false,
            },
          ],
        });
        final config = configuration(policy);
        final route = config['route'] as Map;
        final rules = (route['rules'] as List).cast<Map>();
        final apps = rules
            .where((r) => r.containsKey('process_path_regex'))
            .toList();
        expect(route['find_process'], true);
        expect(
          route['final'],
          mode == TunApplicationRoutingMode.whitelist
              ? 'direct'
              : 'xray-socks-out',
        );
        expect(apps.length, 3);
        expect(apps.first['action'], 'reject'); // Exact path precedes filename.
        expect(apps[1]['outbound'], 'xray-socks-out');
        expect(apps[2]['outbound'], 'direct');
        expect(rules.any((r) => r.containsKey('domain_suffix')), false);
        final expression =
            (apps[1]['process_path_regex'] as List).single as String;
        final matcher = RegExp(expression.substring(4), caseSensitive: false);
        expect(matcher.hasMatch(r'C:\Program Files\SAME.EXE'), true);
        expect(matcher.hasMatch(r'C:\Apps\not-same.exe'), false);
        expect(matcher.hasMatch(r'C:\Apps\same.exe.evil'), false);
        expect(
          rules.indexOf(apps.first),
          greaterThan(rules.indexWhere((r) => r['action'] == 'hijack-dns')),
        );
        expect(
          rules.indexOf(apps.first),
          greaterThan(
            rules.indexWhere(
              (r) =>
                  r['ip_cidr'] is List &&
                  (r['ip_cidr'] as List).contains('203.0.113.7/32'),
            ),
          ),
        );
        expect(
          ((config['dns'] as Map)['servers'] as List)
              .where((s) => s['tag'] == 'remote')
              .single['detour'],
          'xray-socks-out',
        );
      },
    );
  }

  test(
    'empty whitelist routes unknown applications directly without process polling',
    () {
      final route =
          configuration(
                const TunApplicationRouting(
                  enabled: true,
                  mode: TunApplicationRoutingMode.whitelist,
                ),
              )['route']
              as Map;
      expect(route['final'], 'direct');
      expect(route.containsKey('find_process'), false);
    },
  );

  test(
    'literal names and exact paths cannot act as regular expression injections',
    () {
      final route =
          configuration(
                TunApplicationRouting.fromJson({
                  'enabled': true,
                  'rules': [
                    {'processName': 'Game[1]+(x).exe', 'action': 'proxy'},
                    {
                      'processPath': r'D:\Игры\Game[1]+(x).exe',
                      'action': 'block',
                    },
                  ],
                }),
              )['route']
              as Map;
      final apps = (route['rules'] as List)
          .cast<Map>()
          .where((r) => r.containsKey('process_path_regex'))
          .toList();
      RegExp expression(Map rule) => RegExp(
        (rule['process_path_regex'] as List).single.toString().substring(4),
        caseSensitive: false,
      );
      final path = expression(apps.first);
      expect(path.hasMatch(r'D:\Игры\GAME[1]+(X).EXE'), true);
      expect(path.hasMatch(r'D:\Other\Game[1]+(x).exe'), false);
      expect(path.hasMatch(r'D:\Игры\Game111x.exe'), false);
      expect(path.hasMatch(r'C:\D:\Игры\Game[1]+(x).exe'), false);
      final name = expression(apps.last);
      expect(name.hasMatch(r'C:\Apps\Game[1]+(x).exe'), true);
      expect(name.hasMatch('Game[1]+(x).exe'), true);
      expect(name.hasMatch(r'C:\Apps\Game111x.exe'), false);
      expect(name.hasMatch(r'C:\Apps\fakeGame[1]+(x).exe'), false);
    },
  );

  test(
    'programmatically invalid application identities are refused before native generation',
    () {
      expect(
        () => configuration(
          const TunApplicationRouting(
            enabled: true,
            rules: [
              TunApplicationRule(
                match: TunApplicationMatch.processName,
                value: '*.exe',
                action: TunApplicationAction.proxy,
              ),
            ],
          ),
        ),
        throwsFormatException,
      );
    },
  );
}
