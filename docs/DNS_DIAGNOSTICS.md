# DNS diagnostics

Open **Settings → Ping → Diagnostics** (**Настройки → Ping → Диагностика**).
With VPN stopped, confirm that the app may compare public resolvers and save the
best reliable encrypted pair. The dialog shows progress, addresses, reachability,
latency/loss and the final saved result. The operation may take a few minutes.

## Exact resolver pairs

| Provider | First address | Second address | DoT certificate identity |
| --- | --- | --- | --- |
| Yandex | `77.88.8.8` | `77.88.8.1` | `common.dot.dns.yandex.net` |
| Cloudflare | `1.1.1.1` | `1.0.0.1` | `one.one.one.one` |
| Google | `8.8.8.8` | `8.8.4.4` | `dns.google` |
| Quad9 | `9.9.9.9` | `149.112.112.112` | `dns.quad9.net` |
| AdGuard | `94.140.14.14` | `94.140.15.15` | `dns.adguard-dns.com` |
| OpenDNS | `208.67.222.222` | `208.67.220.220` | Exact IP; no assumed hostname |
| Control D | `76.76.2.0` | `76.76.10.0` | `p0.freedns.controld.com` |

Every literal address is tested sequentially with **3 ICMP echoes, 3 UDP DNS
queries to port 53 and 3 TLS-verified DoT queries to port 853**: 126 measurements.
The only query names are `example.com`, `example.net`, and `example.org`.
The TLS identity is used for SNI/certificate verification, not resolved through
another bootstrap resolver. There is no certificate-verification bypass.

UDP responses must come from the exact target address/port and match the query
ID/name/type. DNS message size, names/compression/CNAME chains, record count and
TCP framing are bounded. Truncated, malformed, negative or unusable/private-IP
answers do not count as a usable answer for these example domains. DoT has a
two-second overall connection/handshake/reply budget; probes are closed on
completion, timeout and cancellation.

## Selection and persistence

1. **Both addresses** must return at least **2 of 3 valid DoT answers**. ICMP or
   ordinary DNS success alone cannot qualify a pair. OpenDNS is still measured,
   but is not auto-selected unless DoT verifies successfully against its exact IP.
2. Rank eligible pairs by encrypted-answer success count, then the average of
   their per-address median DoT latency. ICMP is only an informational tie-breaker;
   blocking ICMP alone does not exclude a working encrypted resolver.
3. Within the chosen provider, the more reliable/faster address becomes primary
   and the other becomes backup. The app atomically saves both addresses into
   its existing settings without resetting appearance, language or onboarding.
4. The saved pair survives dialog/application closure and restart. It applies on
   the **next TUN connection**; Proxy mode resolves names on its server. The
   diagnostic itself starts neither engine and changes no Windows DNS adapter.

Canceling, closing the dialog, activating VPN or manually changing DNS while
the check is running prevents it from saving a stale result. If no pair qualifies
or storage fails, the previous saved DNS remains unchanged. Manual primary-DNS
changes clear stale backups; imported arbitrary/cross-provider backups are rejected.
Old single-DNS settings remain compatible.

The TUN mapper uses same-provider TLS resolvers with two-second evaluation/route
timeouts. A failed primary can use the encrypted backup; valid NOERROR/NXDOMAIN
answers are retained instead of retrying a different provider. There is no
ordinary-DNS fallback for TUN user queries. Direct bootstrap/server-resolution
rules are separate from those tunneled queries.

## Privacy and limits

- These are deliberate **direct-network** probes: your current network and the
  chosen public providers receive the example-domain queries. Ordinary UDP DNS
  and ICMP measurements are not encrypted; DoT is certificate-verified TLS.
- Browsing history, server profiles, subscriptions and credentials are not used
  or uploaded. No diagnostics run automatically at startup.
- Providers have different filtering policies, including malicious-domain/ad
  filtering. The shortest reliable sample is not necessarily your preferred policy.
- This is a reachability/latency comparison, **not DNSSEC, censorship, provider
  privacy, kill-switch or traffic/DNS-leak certification**. Conditions may change.
- Automated checks use mocked probes and offline `sing-box check` only. No live
  Proxy/TUN test or actual provider reachability test was performed on the user's machine.
