import 'package:flutter_test/flutter_test.dart';
import 'package:flux/engines/xray/system_proxy_lease.dart';
import 'package:win32_registry/win32_registry.dart';

void main() {
  test(
    'restores an existing enabled proxy and preserves unrelated PAC/bypass settings',
    () {
      final store = MemoryProxySettings({
        'ProxyEnable': const RegistryValue.dword(1),
        'ProxyServer': const RegistryValue.string('corporate.example:8080'),
        'ProxyOverride': const RegistryValue.string('<local>'),
        'AutoConfigURL': const RegistryValue.string(
          'https://corporate.example/proxy.pac',
        ),
      });
      final original = Map.of(store.values);
      final lease = SystemProxyLease(store)..enable(httpPort: 10809);
      expect(
        store.values['ProxyServer'],
        const RegistryValue.string('127.0.0.1:10809'),
      );
      lease.restore();
      expect(store.values, original);
      expect(store.notifications, 2);
      lease.restore(); // Process-exit and stop callbacks may both restore.
      expect(store.notifications, 2);
    },
  );

  test(
    'restores missing values by deleting only the two values it created',
    () {
      final store = MemoryProxySettings({
        'Unrelated': const RegistryValue.string('keep'),
      });
      final lease = SystemProxyLease(store)..enable(httpPort: 10809);
      lease.restore();
      expect(store.values, {'Unrelated': const RegistryValue.string('keep')});
    },
  );

  test('stop without a started lease never changes the real or test proxy', () {
    final store = MemoryProxySettings({
      'ProxyEnable': const RegistryValue.dword(1),
    });
    SystemProxyLease(store).restore();
    expect(store.values['ProxyEnable'], const RegistryValue.dword(1));
    expect(store.writes, isEmpty);
  });

  test(
    'does not overwrite another application taking ownership during the connection',
    () {
      final store = MemoryProxySettings({});
      final lease = SystemProxyLease(store)..enable(httpPort: 10809);
      store.values['ProxyServer'] = const RegistryValue.string(
        'other.example:9000',
      );
      lease.restore();
      expect(store.values['ProxyEnable'], const RegistryValue.dword(1));
      expect(
        store.values['ProxyServer'],
        const RegistryValue.string('other.example:9000'),
      );
    },
  );

  test(
    'keeps a user disabling the proxy, but removes our stale ProxyServer',
    () {
      final store = MemoryProxySettings({
        'ProxyEnable': const RegistryValue.dword(1),
      });
      final lease = SystemProxyLease(store)..enable(httpPort: 10809);
      store.values['ProxyEnable'] = const RegistryValue.dword(0);
      lease.restore();
      expect(store.values['ProxyEnable'], const RegistryValue.dword(0));
      expect(store.values.containsKey('ProxyServer'), false);
    },
  );

  test('a partial enable failure rolls back the original values', () {
    final store = MemoryProxySettings({
      'ProxyEnable': const RegistryValue.dword(0),
      'ProxyServer': const RegistryValue.unexpandedString(
        '%CORPORATE_PROXY%:8080',
      ),
    });
    final original = Map.of(store.values);
    store.failNextWrite = 'ProxyEnable';
    expect(
      () => SystemProxyLease(store).enable(httpPort: 10809),
      throwsStateError,
    );
    expect(store.values, original);
  });

  test(
    'a failed restore can be retried without losing the original snapshot',
    () {
      final store = MemoryProxySettings({
        'ProxyEnable': const RegistryValue.dword(0),
      });
      final lease = SystemProxyLease(store)..enable(httpPort: 10809);
      store.failNextWrite = 'ProxyServer';
      expect(lease.restore, throwsStateError);
      lease.restore();
      expect(store.values, {'ProxyEnable': const RegistryValue.dword(0)});
    },
  );
}

class MemoryProxySettings implements ProxySettingsStore {
  final Map<String, RegistryValue> values;
  final writes = <String>[];
  int notifications = 0;
  String? failNextWrite;

  MemoryProxySettings(this.values);
  @override
  RegistryValue? read(String name) => values[name];
  @override
  void write(String name, RegistryValue? value) {
    if (failNextWrite == name) {
      failNextWrite = null;
      throw StateError('Injected registry write failure');
    }
    writes.add(name);
    if (value == null) {
      values.remove(name);
    } else {
      values[name] = value;
    }
  }

  @override
  void notifyChanged() => notifications++;
}
