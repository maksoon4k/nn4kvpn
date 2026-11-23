import 'dart:convert';

/// Small bounded A-query codec. No system resolver, user browsing names,
/// external commands or dependencies are used to validate a DNS reply.
class DnsWire {
  static const maxMessageBytes = 4096;

  static List<int> query(String domain, int id) {
    final labels = domain.split('.');
    if (id < 0 ||
        id > 65535 ||
        domain.length > 253 ||
        labels.any(
          (label) =>
              label.isEmpty ||
              label.length > 63 ||
              !RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(label),
        )) {
      throw const FormatException('Invalid diagnostic query name');
    }
    return [
      id >> 8,
      id & 255,
      1,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      for (final label in labels) ...[label.length, ...ascii.encode(label)],
      0,
      0,
      1,
      0,
      1,
    ];
  }

  static bool isUsableAnswer(List<int> bytes, String domain, int id) {
    try {
      if (bytes.length < 12 ||
          bytes.length > maxMessageBytes ||
          _u16(bytes, 0) != id ||
          (bytes[2] & 0xfa) != 0x80 ||
          (bytes[3] & 15) != 0 ||
          _u16(bytes, 4) != 1 ||
          _u16(bytes, 6) == 0 ||
          _u16(bytes, 6) > 128) {
        return false;
      }
      final question = _name(bytes, 12);
      if (question.$1.toLowerCase() != domain.toLowerCase() ||
          _u16(bytes, question.$2) != 1 ||
          _u16(bytes, question.$2 + 2) != 1) {
        return false;
      }
      var offset = question.$2 + 4;
      final answers = _u16(bytes, 6);
      final records = answers + _u16(bytes, 8) + _u16(bytes, 10);
      if (records > 128) return false;
      final aliases = <String, String>{};
      final usableOwners = <String>{};
      for (var record = 0; record < records; record++) {
        final owner = _name(bytes, offset);
        offset = owner.$2;
        final type = _u16(bytes, offset);
        final klass = _u16(bytes, offset + 2);
        final length = _u16(bytes, offset + 8);
        offset += 10;
        if (offset + length > bytes.length) return false;
        if (record < answers && klass == 1) {
          if (type == 1) {
            if (length != 4) return false;
            if (_publicIpv4(bytes.sublist(offset, offset + 4))) {
              usableOwners.add(owner.$1.toLowerCase());
            }
          } else if (type == 5) {
            final alias = _name(bytes, offset);
            if (alias.$2 != offset + length) return false;
            aliases[owner.$1.toLowerCase()] = alias.$1.toLowerCase();
          }
        }
        offset += length;
      }
      if (offset != bytes.length) return false;
      var name = domain.toLowerCase();
      final visited = <String>{};
      for (var step = 0; step < 16; step++) {
        if (!visited.add(name)) return false;
        if (usableOwners.contains(name)) return true;
        final alias = aliases[name];
        if (alias == null) return false;
        name = alias;
      }
      return false;
    } on FormatException {
      return false;
    } on RangeError {
      return false;
    }
  }

  static bool _publicIpv4(List<int> ip) =>
      ip[0] != 0 &&
      ip[0] != 10 &&
      ip[0] != 127 &&
      ip[0] < 224 &&
      !(ip[0] == 169 && ip[1] == 254) &&
      !(ip[0] == 100 && ip[1] >= 64 && ip[1] <= 127) &&
      !(ip[0] == 172 && ip[1] >= 16 && ip[1] <= 31) &&
      !(ip[0] == 192 &&
          (ip[1] == 168 || (ip[1] == 0 && (ip[2] == 0 || ip[2] == 2)))) &&
      !(ip[0] == 198 &&
          (ip[1] == 18 || ip[1] == 19 || (ip[1] == 51 && ip[2] == 100))) &&
      !(ip[0] == 203 && ip[1] == 0 && ip[2] == 113);

  static int _u16(List<int> bytes, int offset) =>
      (bytes[offset] << 8) | bytes[offset + 1];

  static (String, int) _name(List<int> bytes, int start) {
    var offset = start;
    int? end;
    final visited = <int>{};
    final labels = <String>[];
    var nameBytes = 0;
    for (var step = 0; step < 128; step++) {
      if (!visited.add(offset)) throw const FormatException('DNS name loop');
      final size = bytes[offset++];
      if (size == 0) return (labels.join('.'), end ?? offset);
      if ((size & 0xc0) == 0xc0) {
        final pointer = ((size & 63) << 8) | bytes[offset++];
        if (pointer < 12 || pointer >= offset - 2) {
          throw const FormatException('Invalid DNS compression pointer');
        }
        end ??= offset;
        offset = pointer;
        continue;
      }
      nameBytes += size + 1;
      if (size > 63 || nameBytes > 254 || offset + size > bytes.length) {
        throw const FormatException('Invalid DNS name');
      }
      labels.add(ascii.decode(bytes.sublist(offset, offset + size)));
      offset += size;
    }
    throw const FormatException('DNS name exceeds limit');
  }
}

/// A single DNS-over-TCP length-prefixed response, accumulated with a strict
/// byte budget. [add] returns null until complete and never retains extra data
/// after accepting/rejecting the first frame.
class DnsTcpAnswerReader {
  final String domain;
  final int id;
  final _bytes = <int>[];
  bool? _result;
  DnsTcpAnswerReader(this.domain, this.id);

  bool? add(List<int> chunk) {
    if (_result != null) return _result;
    if (_bytes.length + chunk.length > DnsWire.maxMessageBytes + 2) {
      return _result = false;
    }
    _bytes.addAll(chunk);
    if (_bytes.length < 2) return null;
    final size = (_bytes[0] << 8) | _bytes[1];
    if (size < 12 || size > DnsWire.maxMessageBytes) return _result = false;
    if (_bytes.length < size + 2) return null;
    return _result = DnsWire.isUsableAnswer(
      _bytes.sublist(2, size + 2),
      domain,
      id,
    );
  }
}
