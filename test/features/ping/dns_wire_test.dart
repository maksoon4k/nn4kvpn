import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux/features/ping/dns_wire.dart';
import 'package:flux/features/ping/windows_dns_probe.dart';

const diagnosticId = 0x1234;
List<int> encodedDnsName(String name) => [
  for (final label in name.split('.')) ...[
    label.length,
    ...ascii.encode(label),
  ],
  0,
];

List<int> answer({
  List<int> ip = const [93, 184, 216, 34],
  List<int> owner = const [0xc0, 12],
}) {
  final query = DnsWire.query('example.com', diagnosticId)
    ..[2] = 0x81
    ..[3] = 0x80
    ..[7] = 1;
  return [...query, ...owner, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, ...ip];
}

void main() {
  bool usable(List<int> bytes) =>
      DnsWire.isUsableAnswer(bytes, 'example.com', diagnosticId);

  test('builds an exact recursive A/IN query without system DNS', () {
    expect(DnsWire.query('example.com', diagnosticId), [
      0x12,
      0x34,
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
      7,
      ...ascii.encode('example'),
      3,
      ...ascii.encode('com'),
      0,
      0,
      1,
      0,
      1,
    ]);
    for (final name in [
      '',
      'a..com',
      '${'a' * 64}.com',
      'bad/name.com',
      'я.рф',
    ]) {
      expect(() => DnsWire.query(name, diagnosticId), throwsFormatException);
    }
    expect(() => DnsWire.query('example.com', -1), throwsFormatException);
    expect(() => DnsWire.query('example.com', 65536), throwsFormatException);
  });

  test(
    'requires a matching question/id, non-truncated successful reply and a public A answer',
    () {
      expect(usable(answer()), true);
      final wrongId = answer()..[1] ^= 1;
      final truncated = answer()..[2] |= 2;
      final nxdomain = answer()..[3] |= 3;
      final opcode = answer()..[2] |= 8;
      final notResponse = answer()..[2] &= 0x7f;
      for (final bytes in [wrongId, truncated, nxdomain, opcode, notResponse]) {
        expect(usable(bytes), false);
      }
      expect(
        DnsWire.isUsableAnswer(answer(), 'example.net', diagnosticId),
        false,
      );
      expect(usable(answer(owner: encodedDnsName('unrelated.example'))), false);
    },
  );

  test(
    'rejects private, loopback, CGNAT and documentation sinkhole addresses',
    () {
      for (final ip in [
        [0, 0, 0, 0],
        [10, 0, 0, 1],
        [127, 0, 0, 1],
        [169, 254, 1, 2],
        [172, 16, 0, 1],
        [192, 168, 1, 1],
        [100, 64, 1, 1],
        [192, 0, 2, 1],
        [198, 51, 100, 1],
        [203, 0, 113, 1],
        [224, 1, 1, 1],
      ]) {
        expect(usable(answer(ip: ip)), false);
      }
    },
  );

  test('accepts a bounded matching CNAME-to-A chain', () {
    final query = DnsWire.query('example.com', diagnosticId)
      ..[2] = 0x81
      ..[3] = 0x80
      ..[7] = 2;
    final target = encodedDnsName('alias.example.com');
    final targetOffset = query.length + 12;
    final bytes = [
      ...query,
      0xc0,
      12,
      0,
      5,
      0,
      1,
      0,
      0,
      0,
      60,
      0,
      target.length,
      ...target,
      0xc0 | (targetOffset >> 8),
      targetOffset & 255,
      0,
      1,
      0,
      1,
      0,
      0,
      0,
      60,
      0,
      4,
      93,
      184,
      216,
      34,
    ];
    expect(usable(bytes), true);
  });

  test(
    'malformed/truncated/oversized messages and compression loops fail closed',
    () {
      final valid = answer();
      for (var length = 0; length < valid.length; length++) {
        expect(usable(valid.sublist(0, length)), false);
      }
      for (final owner in [
        [0xc0, 0],
        [0xc0, 255],
        [0xc0, 29],
      ]) {
        expect(usable(answer(owner: owner)), false);
      }
      final malformedExtra = answer()..[11] = 1;
      expect(usable(malformedExtra), false);
      expect(usable([...valid, 0]), false);
      expect(usable(List.filled(DnsWire.maxMessageBytes + 1, 0)), false);
      expect(usable(answer()..[7] = 129), false);
    },
  );

  test(
    'DoT frame accepts fragmented length/header/body and retains a terminal result',
    () {
      final bytes = answer();
      final framed = [bytes.length >> 8, bytes.length & 255, ...bytes];
      final reader = DnsTcpAnswerReader('example.com', diagnosticId);
      for (var index = 0; index < framed.length - 1; index++) {
        expect(reader.add([framed[index]]), isNull);
      }
      expect(reader.add([framed.last]), true);
      expect(reader.add(List.filled(10000, 0)), true);
    },
  );

  test('DoT frame rejects zero/huge lengths and byte-budget abuse', () {
    for (final frame in [
      [0, 0],
      [255, 255],
      List<int>.filled(5000, 0),
    ]) {
      final reader = DnsTcpAnswerReader('example.com', diagnosticId);
      expect(reader.add(frame), false);
      expect(reader.add([1, 2, 3]), false);
    }
  });

  test(
    'Windows ICMP parser works in English/Russian and rejects failed echoes',
    () {
      expect(
        WindowsDnsProbe.parseWindowsEcho(
          'Reply from 1.1.1.1: bytes=32 time=15ms TTL=58',
          0,
        ),
        15,
      );
      expect(
        WindowsDnsProbe.parseWindowsEcho(
          'Ответ от 1.1.1.1: число байт=32 время<1мс TTL=58',
          0,
        ),
        1,
      );
      expect(WindowsDnsProbe.parseWindowsEcho('Request timed out.', 1), isNull);
      expect(
        WindowsDnsProbe.parseWindowsEcho('Destination host unreachable.', 0),
        isNull,
      );
      expect(WindowsDnsProbe.parseWindowsEcho('time=12ms TTL=58', 1), isNull);
    },
  );
}
