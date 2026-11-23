enum TunApplicationRoutingMode { whitelist, blacklist }

enum TunApplicationAction { direct, proxy, block }

enum TunApplicationMatch { processName, processPath }

/// Stable application identities, not transient PIDs. An exact executable path
/// takes precedence over a filename rule; no file needs to exist at edit time.
class TunApplicationRule {
  final TunApplicationMatch match;
  final String value;
  final TunApplicationAction action;
  final bool enabled;

  const TunApplicationRule({
    required this.match,
    required this.value,
    required this.action,
    this.enabled = true,
  });

  String get identity =>
      '${match.name}:${value.replaceAll('/', '\\').toLowerCase()}';

  factory TunApplicationRule.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException(
        'Правило приложения должно быть JSON-объектом.',
      );
    }
    final keys = raw.keys.toSet();
    if (keys.difference({
      'processName',
      'processPath',
      'action',
      'enabled',
    }).isNotEmpty) {
      throw const FormatException(
        'В правиле допустимы processName/processPath, action и enabled.',
      );
    }
    final name = raw['processName'];
    final path = raw['processPath'];
    if ((name == null) == (path == null)) {
      throw const FormatException(
        'Укажите ровно одно поле: processName или processPath.',
      );
    }
    final target = name ?? path;
    if (target is! String ||
        target.trim().isEmpty ||
        RegExp(r'[\x00-\x1f"*?<>|]').hasMatch(target)) {
      throw const FormatException(
        'Нужно точное имя .exe или абсолютный путь, без масок и управляющих символов.',
      );
    }
    var value = target.trim();
    if (!value.toLowerCase().endsWith('.exe')) {
      throw const FormatException(
        'Укажите исполняемый файл с расширением .exe.',
      );
    }
    if (name != null) {
      if (value.length > 260 || RegExp(r'[/\\:]').hasMatch(value)) {
        throw const FormatException(
          'processName содержит только имя файла, например chrome.exe.',
        );
      }
    } else {
      value = value.replaceAll('/', '\\');
      final drivePath = RegExp(r'^[a-zA-Z]:\\').hasMatch(value);
      final pathSegments = value.split('\\').skip(drivePath ? 1 : 2).toList();
      if (value.length > 32760 ||
          !(drivePath || value.startsWith('\\\\')) ||
          (!drivePath && pathSegments.length < 3) ||
          pathSegments.any(
            (segment) =>
                segment.isEmpty ||
                segment == '..' ||
                segment == '.' ||
                segment.contains(':') ||
                segment.endsWith('.') ||
                segment.endsWith(' '),
          )) {
        throw const FormatException(
          'processPath должен быть полным Windows-путём к .exe, без . / .., пустых сегментов или потоков файла.',
        );
      }
    }
    final action = _parseEnum(
      TunApplicationAction.values,
      raw['action'],
      'action',
    );
    final enabled = raw['enabled'] ?? true;
    if (enabled is! bool) {
      throw const FormatException('enabled должен быть true или false.');
    }
    return TunApplicationRule(
      match: name != null
          ? TunApplicationMatch.processName
          : TunApplicationMatch.processPath,
      value: value,
      action: action,
      enabled: enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    match.name: value,
    'action': action.name,
    'enabled': enabled,
  };

  TunApplicationRule copyWith({TunApplicationAction? action, bool? enabled}) =>
      TunApplicationRule(
        match: match,
        value: value,
        action: action ?? this.action,
        enabled: enabled ?? this.enabled,
      );

  @override
  bool operator ==(Object other) =>
      other is TunApplicationRule &&
      match == other.match &&
      value == other.value &&
      action == other.action &&
      enabled == other.enabled;
  @override
  int get hashCode => Object.hash(match, value, action, enabled);
}

class TunApplicationRouting {
  static const maxRules = 512;
  final bool enabled;
  final TunApplicationRoutingMode mode;
  final List<TunApplicationRule> rules;
  final String? validationError;
  final Object? _invalidJson;

  const TunApplicationRouting({
    this.enabled = false,
    this.mode = TunApplicationRoutingMode.blacklist,
    this.rules = const [],
  }) : validationError = null,
       _invalidJson = null;

  const TunApplicationRouting._invalid(this._invalidJson, this.validationError)
    : enabled = false,
      mode = TunApplicationRoutingMode.blacklist,
      rules = const [];

  TunApplicationAction get defaultAction =>
      mode == TunApplicationRoutingMode.whitelist
      ? TunApplicationAction.direct
      : TunApplicationAction.proxy;
  TunApplicationAction get suggestedAction =>
      mode == TunApplicationRoutingMode.whitelist
      ? TunApplicationAction.proxy
      : TunApplicationAction.direct;

  factory TunApplicationRouting.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException(
        'Конфигурация приложений должна быть JSON-объектом.',
      );
    }
    if (raw.keys.toSet().difference({'enabled', 'mode', 'rules'}).isNotEmpty) {
      throw const FormatException('Допустимы только enabled, mode и rules.');
    }
    final enabled = raw['enabled'] ?? false;
    if (enabled is! bool) {
      throw const FormatException('enabled должен быть true или false.');
    }
    final mode = _parseEnum(
      TunApplicationRoutingMode.values,
      raw['mode'] ?? 'blacklist',
      'mode',
    );
    final entries = raw['rules'] ?? const [];
    if (entries is! List || entries.length > maxRules) {
      throw const FormatException('rules — список не более 512 приложений.');
    }
    final rules = entries.map(TunApplicationRule.fromJson).toList();
    final identities = <String>{};
    for (final rule in rules) {
      if (!identities.add(rule.identity)) {
        throw FormatException('Повтор приложения: ${rule.value}');
      }
    }
    return TunApplicationRouting(
      enabled: enabled,
      mode: mode,
      rules: List.unmodifiable(rules),
    );
  }

  /// Keep a malformed hand-edited section intact instead of resetting unrelated
  /// settings. TUN startup refuses it; the JSON editor can repair the original.
  factory TunApplicationRouting.restore(Object? raw) {
    if (raw == null) return const TunApplicationRouting();
    try {
      return TunApplicationRouting.fromJson(raw);
    } on FormatException catch (error) {
      return TunApplicationRouting._invalid(raw, error.message);
    }
  }

  Object toJson() =>
      _invalidJson ??
      {
        'enabled': enabled,
        'mode': mode.name,
        'rules': rules.map((rule) => rule.toJson()).toList(),
      };

  void requireValid() {
    if (validationError != null) throw FormatException(validationError!);
    // Also validate programmatically constructed settings before native use.
    TunApplicationRouting.fromJson(toJson());
  }

  TunApplicationRouting copyWith({
    bool? enabled,
    TunApplicationRoutingMode? mode,
    List<TunApplicationRule>? rules,
  }) => TunApplicationRouting.fromJson({
    'enabled': enabled ?? this.enabled,
    'mode': (mode ?? this.mode).name,
    'rules': (rules ?? this.rules).map((rule) => rule.toJson()).toList(),
  });

  @override
  bool operator ==(Object other) =>
      other is TunApplicationRouting &&
      enabled == other.enabled &&
      mode == other.mode &&
      validationError == other.validationError &&
      _invalidJson == other._invalidJson &&
      rules.length == other.rules.length &&
      List.generate(
        rules.length,
        (i) => rules[i] == other.rules[i],
      ).every((v) => v);
  @override
  int get hashCode => Object.hash(
    enabled,
    mode,
    validationError,
    _invalidJson,
    Object.hashAll(rules),
  );
}

T _parseEnum<T extends Enum>(List<T> values, Object? raw, String key) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  throw FormatException(
    '$key: допустимы ${values.map((v) => v.name).join(', ')}.',
  );
}
