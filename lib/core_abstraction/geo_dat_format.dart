/// Ручной декодер protobuf-wire-формата `geosite.dat`/`geoip.dat`
/// (v2ray/xray-core, https://github.com/v2fly/domain-list-community и
/// https://github.com/Loyalsoldier/v2ray-rules-dat) — см. ROADMAP.md, трек
/// 21. Схема обоих файлов простая (`GeoSiteList`/`GeoIPList` — плоские
/// списки записей по коду страны/категории), так что полноценный
/// protobuf-пакет не подключаем, а читаем wire-формат вручную: varint +
/// length-delimited, без зависимостей.
///
/// Схемы (proto3, для справки — не парсятся из .proto, а зашиты руками):
/// ```proto
/// message GeoSiteList { repeated GeoSite entry = 1; }
/// message GeoSite {
///   string country_code = 1;
///   repeated Domain domain = 2;
/// }
/// message Domain {
///   enum Type { Plain = 0; Regex = 1; Domain = 2; Full = 3; }
///   Type type = 1;
///   string value = 2;
/// }
///
/// message GeoIPList { repeated GeoIP entry = 1; }
/// message GeoIP {
///   string country_code = 1;
///   repeated CIDR cidr = 2;
/// }
/// message CIDR { bytes ip = 1; uint32 prefix = 2; }
/// ```
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

enum GeoDomainType { plain, regex, domain, full }

class GeoDomainEntry {
  final GeoDomainType type;
  final String value;
  const GeoDomainEntry(this.type, this.value);
}

class GeoSiteEntry {
  final String countryCode;
  final List<GeoDomainEntry> domains;
  const GeoSiteEntry(this.countryCode, this.domains);
}

class GeoCidrEntry {
  /// Строковое представление адреса (`1.2.3.0`/`::1`), уже без маски.
  final String ip;
  final int prefix;
  const GeoCidrEntry(this.ip, this.prefix);

  /// `ip/prefix` — формат, который xray/sing-box ожидают в `ip_cidr`.
  String get cidr => '$ip/$prefix';
}

class GeoIpEntry {
  final String countryCode;
  final List<GeoCidrEntry> cidrs;
  const GeoIpEntry(this.countryCode, this.cidrs);
}

/// Правило роутинга ссылается на категорию, которой нет в `.dat`-файле —
/// это ошибка конфигурации сервиса (сервер прописал `geosite:xxx`, которого
/// нет в базе), не повод тихо no-op'нуть правило.
class GeoCategoryNotFoundException implements Exception {
  final String category;
  const GeoCategoryNotFoundException(this.category);

  @override
  String toString() => 'geosite/geoip category not found: $category';
}

List<GeoSiteEntry> parseGeoSiteDat(
  Uint8List bytes, {
  int maxRecords = 2000000,
}) {
  final reader = _ProtoReader(bytes);
  final budget = _ParseBudget(maxRecords);
  final entries = <GeoSiteEntry>[];
  while (reader.hasMore) {
    final tag = reader.readTag();
    if (tag.fieldNumber == 1) {
      tag.requireWireType(_WireType.lengthDelimited);
      entries.add(_parseGeoSite(reader.readLengthDelimited(), budget));
    } else {
      reader.skip(tag.wireType);
    }
  }
  return entries;
}

List<GeoIpEntry> parseGeoIpDat(Uint8List bytes, {int maxRecords = 2000000}) {
  final reader = _ProtoReader(bytes);
  final budget = _ParseBudget(maxRecords);
  final entries = <GeoIpEntry>[];
  while (reader.hasMore) {
    final tag = reader.readTag();
    if (tag.fieldNumber == 1) {
      tag.requireWireType(_WireType.lengthDelimited);
      entries.add(_parseGeoIp(reader.readLengthDelimited(), budget));
    } else {
      reader.skip(tag.wireType);
    }
  }
  return entries;
}

GeoSiteEntry findGeoSiteCategory(List<GeoSiteEntry> entries, String category) {
  for (final entry in entries) {
    if (entry.countryCode.toLowerCase() == category.toLowerCase()) return entry;
  }
  throw GeoCategoryNotFoundException(category);
}

GeoIpEntry findGeoIpCategory(List<GeoIpEntry> entries, String category) {
  for (final entry in entries) {
    if (entry.countryCode.toLowerCase() == category.toLowerCase()) return entry;
  }
  throw GeoCategoryNotFoundException(category);
}

GeoSiteEntry _parseGeoSite(Uint8List bytes, _ParseBudget budget) {
  budget.take();
  final reader = _ProtoReader(bytes);
  var countryCode = '';
  final domains = <GeoDomainEntry>[];
  while (reader.hasMore) {
    final tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:
        tag.requireWireType(_WireType.lengthDelimited);
        countryCode = _utf8(reader.readLengthDelimited());
      case 2:
        tag.requireWireType(_WireType.lengthDelimited);
        domains.add(_parseDomain(reader.readLengthDelimited(), budget));
      default:
        reader.skip(tag.wireType);
    }
  }
  if (countryCode.isEmpty) throw const FormatException('Missing geo category');
  return GeoSiteEntry(countryCode, domains);
}

GeoDomainEntry _parseDomain(Uint8List bytes, _ParseBudget budget) {
  budget.take();
  final reader = _ProtoReader(bytes);
  var type = GeoDomainType.plain;
  var value = '';
  while (reader.hasMore) {
    final tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:
        tag.requireWireType(_WireType.varint);
        type = _domainType(reader.readVarint());
      case 2:
        tag.requireWireType(_WireType.lengthDelimited);
        value = _utf8(reader.readLengthDelimited());
      default:
        reader.skip(tag.wireType);
    }
  }
  if (value.isEmpty) throw const FormatException('Missing geo domain');
  return GeoDomainEntry(type, value);
}

GeoDomainType _domainType(int raw) => switch (raw) {
  0 => GeoDomainType.plain,
  1 => GeoDomainType.regex,
  2 => GeoDomainType.domain,
  3 => GeoDomainType.full,
  _ => throw const FormatException('Unknown geo domain type'),
};

GeoIpEntry _parseGeoIp(Uint8List bytes, _ParseBudget budget) {
  budget.take();
  final reader = _ProtoReader(bytes);
  var countryCode = '';
  final cidrs = <GeoCidrEntry>[];
  while (reader.hasMore) {
    final tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:
        tag.requireWireType(_WireType.lengthDelimited);
        countryCode = _utf8(reader.readLengthDelimited());
      case 2:
        tag.requireWireType(_WireType.lengthDelimited);
        cidrs.add(_parseCidr(reader.readLengthDelimited(), budget));
      default:
        reader.skip(tag.wireType);
    }
  }
  if (countryCode.isEmpty) throw const FormatException('Missing geo category');
  return GeoIpEntry(countryCode, cidrs);
}

GeoCidrEntry _parseCidr(Uint8List bytes, _ParseBudget budget) {
  budget.take();
  final reader = _ProtoReader(bytes);
  Uint8List ip = Uint8List(0);
  var prefix = 0;
  while (reader.hasMore) {
    final tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:
        tag.requireWireType(_WireType.lengthDelimited);
        ip = reader.readLengthDelimited();
      case 2:
        tag.requireWireType(_WireType.varint);
        prefix = reader.readVarint();
      default:
        reader.skip(tag.wireType);
    }
  }
  if ((ip.length != 4 && ip.length != 16) ||
      prefix < 0 ||
      prefix > ip.length * 8) {
    throw const FormatException('Invalid geo CIDR');
  }
  return GeoCidrEntry(InternetAddress.fromRawAddress(ip).address, prefix);
}

String _utf8(Uint8List bytes) => utf8.decode(bytes);

enum _WireType { varint, fixed64, lengthDelimited, fixed32 }

class _Tag {
  final int fieldNumber;
  final _WireType wireType;
  const _Tag(this.fieldNumber, this.wireType);

  void requireWireType(_WireType expected) {
    if (wireType != expected) {
      throw const FormatException('Invalid protobuf field type');
    }
  }
}

class _ParseBudget {
  final int maxRecords;
  int _records = 0;
  _ParseBudget(this.maxRecords) {
    if (maxRecords < 1) throw RangeError.value(maxRecords, 'maxRecords');
  }

  void take() {
    if (++_records > maxRecords) {
      throw const FormatException('Geo database exceeds the record limit');
    }
  }
}

class _ProtoReader {
  final Uint8List _bytes;
  int _pos = 0;

  _ProtoReader(this._bytes);

  bool get hasMore => _pos < _bytes.length;

  _Tag readTag() {
    final key = readVarint();
    final fieldNumber = key >> 3;
    if (fieldNumber < 1 || fieldNumber > 0x1fffffff) {
      throw const FormatException('Invalid protobuf field number');
    }
    final wireType = switch (key & 0x7) {
      0 => _WireType.varint,
      1 => _WireType.fixed64,
      2 => _WireType.lengthDelimited,
      5 => _WireType.fixed32,
      final other => throw FormatException('Unknown protobuf wire type $other'),
    };
    return _Tag(fieldNumber, wireType);
  }

  int readVarint() {
    var result = 0;
    var shift = 0;
    for (var i = 0; i < 10; i++) {
      _requireBytes(1);
      final byte = _bytes[_pos++];
      if (i == 9 && byte > 1) {
        throw const FormatException('Protobuf varint overflow');
      }
      result |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
    }
    throw const FormatException('Protobuf varint overflow');
  }

  Uint8List readLengthDelimited() {
    final length = readVarint();
    _requireBytes(length);
    final result = Uint8List.sublistView(_bytes, _pos, _pos + length);
    _pos += length;
    return result;
  }

  void skip(_WireType wireType) {
    switch (wireType) {
      case _WireType.varint:
        readVarint();
      case _WireType.lengthDelimited:
        readLengthDelimited();
      case _WireType.fixed64:
        _requireBytes(8);
        _pos += 8;
      case _WireType.fixed32:
        _requireBytes(4);
        _pos += 4;
    }
  }

  void _requireBytes(int count) {
    if (count < 0 || count > _bytes.length - _pos) {
      throw const FormatException('Truncated protobuf data');
    }
  }
}
