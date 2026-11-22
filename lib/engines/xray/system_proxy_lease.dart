import 'package:win32_registry/win32_registry.dart';

/// Injectable registry access; tests never change the real Windows proxy.
abstract interface class ProxySettingsStore {
  RegistryValue? read(String name);
  void write(String name, RegistryValue? value);
  void notifyChanged();
}

/// Owns only the proxy values set by one engine. Restores their original value
/// and type instead of always disabling a user's pre-existing corporate proxy.
class SystemProxyLease {
  final ProxySettingsStore settings;
  RegistryValue? _originalEnable;
  RegistryValue? _originalServer;
  StringValue? _ownedServer;

  SystemProxyLease(this.settings);

  void enable({required int httpPort}) {
    if (httpPort < 1 || httpPort > 65535) {
      throw RangeError.range(httpPort, 1, 65535, 'httpPort');
    }
    if (_ownedServer != null) {
      throw StateError('This engine already owns a system proxy lease');
    }
    _originalEnable = settings.read('ProxyEnable');
    _originalServer = settings.read('ProxyServer');
    final server = RegistryValue.string('127.0.0.1:$httpPort') as StringValue;
    try {
      // Set the destination before enabling it, never temporarily enabling an
      // unrelated ProxyServer left over in the registry.
      settings.write('ProxyServer', server);
      _ownedServer = server;
      settings.write('ProxyEnable', const RegistryValue.dword(1));
      settings.notifyChanged();
    } catch (_) {
      restore();
      rethrow;
    }
  }

  void restore() {
    final ownedServer = _ownedServer;
    if (ownedServer == null) {
      return; // stop() without a start() changes nothing.
    }
    // Another application/user has taken over: do not disable their proxy.
    if (settings.read('ProxyServer') == ownedServer) {
      if (settings.read('ProxyEnable') == const RegistryValue.dword(1)) {
        settings.write('ProxyEnable', _originalEnable);
      }
      settings.write('ProxyServer', _originalServer);
      settings.notifyChanged();
    }
    // Retain the snapshot if a restore write fails, so stop() can be retried.
    _ownedServer = null;
    _originalEnable = null;
    _originalServer = null;
  }
}
