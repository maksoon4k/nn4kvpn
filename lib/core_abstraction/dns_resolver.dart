/// Curated public DNS pairs. Addresses are dialed literally; TLS names are
/// used for certificate verification/SNI, never resolved as another bootstrap.
class DnsResolverPair {
  final String name;
  final String primary;
  final String secondary;
  final String? tlsServerName;

  const DnsResolverPair(
    this.name,
    this.primary,
    this.secondary,
    this.tlsServerName,
  );

  List<String> get addresses => [primary, secondary];
}

const diagnosticDnsPairs = [
  DnsResolverPair(
    'Yandex',
    '77.88.8.8',
    '77.88.8.1',
    'common.dot.dns.yandex.net',
  ),
  DnsResolverPair('Cloudflare', '1.1.1.1', '1.0.0.1', 'one.one.one.one'),
  DnsResolverPair('Google', '8.8.8.8', '8.8.4.4', 'dns.google'),
  DnsResolverPair('Quad9', '9.9.9.9', '149.112.112.112', 'dns.quad9.net'),
  DnsResolverPair(
    'AdGuard',
    '94.140.14.14',
    '94.140.15.15',
    'dns.adguard-dns.com',
  ),
  // No assumed DoT hostname: still measure ICMP, UDP DNS and certificate-
  // verified DoT to the exact IP. Plain-only resolvers cannot be auto-selected.
  DnsResolverPair('OpenDNS', '208.67.222.222', '208.67.220.220', null),
  DnsResolverPair(
    'Control D',
    '76.76.2.0',
    '76.76.10.0',
    'p0.freedns.controld.com',
  ),
];

String? dnsTlsServerNameFor(String address) {
  for (final pair in diagnosticDnsPairs) {
    if (pair.primary == address || pair.secondary == address) {
      return pair.tlsServerName;
    }
  }
  return null;
}

bool dnsAddressesShareProvider(String primary, String secondary) =>
    primary != secondary &&
    diagnosticDnsPairs.any(
      (pair) =>
          pair.addresses.contains(primary) &&
          pair.addresses.contains(secondary),
    );
