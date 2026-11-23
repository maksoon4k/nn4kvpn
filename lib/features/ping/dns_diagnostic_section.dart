import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core_abstraction/app_settings.dart';
import '../../core_abstraction/app_settings_provider.dart';
import '../../core_abstraction/dns_resolver.dart';
import '../../l10n/app_locale.dart';
import '../../widgets/port_ui/port_ui.dart';
import '../connection/connection_controller.dart';
import '../connection/connection_state.dart';
import 'dns_diagnostic_controller.dart';
import 'dns_diagnostic_service.dart';

class DnsDiagnosticStrings {
  static bool get en => AppLocale.effective == AppLanguage.en;
  static String get title => en ? 'DNS diagnostics' : 'Диагностика DNS';
  static String get button => en ? 'Diagnostics' : 'Диагностика';
  static String get cancel => en ? 'Cancel' : 'Отмена';
  static String get close => en ? 'Close' : 'Закрыть';
  static String get start => en ? 'Start diagnostics' : 'Начать диагностику';
  static String get confirmation => en
      ? 'Start diagnostics and automatically save the best working DNS pair? With VPN off, the app will test 14 addresses in sequence: 3 ICMP echoes, 3 ordinary DNS queries and 3 certificate-verified encrypted DNS (DoT) queries per address. Only example.com, example.net and example.org are queried, directly over your current network. This may take a few minutes. Reliability comes before latency; both addresses must provide at least 2 of 3 valid DoT replies. Some providers filter ads or malicious domains. Windows DNS settings are not changed. You can cancel without changing your saved DNS.'
      : 'Начать диагностику и автоматически сохранить лучшую рабочую пару DNS? При выключенном VPN приложение по очереди проверит 14 адресов: по 3 ICMP-пинга, 3 обычных DNS-запроса и 3 зашифрованных DNS-запроса (DoT) с проверкой сертификата. Запрашиваются только example.com, example.net и example.org — напрямую через вашу текущую сеть. Проверка может занять несколько минут. Надёжность важнее задержки: каждый адрес должен дать хотя бы 2 из 3 корректных DoT-ответов. Некоторые провайдеры фильтруют рекламу или опасные домены. DNS Windows не меняется. Отмена сохранит прежний выбор.';
  static String get help => en
      ? 'Compare 7 public DNS pairs and save a reliable encrypted resolver for TUN. No VPN connection is started. Applies on your next TUN connection; Proxy mode resolves names on its server.'
      : 'Сравнить 7 публичных пар DNS и сохранить надёжный зашифрованный резолвер для TUN. VPN не запускается. Выбор применится при следующем подключении TUN; в Proxy имена разрешает сервер.';
  static String selected(String primary, String secondary) => en
      ? 'Saved DNS: $primary${secondary.isEmpty ? '' : ' / $secondary'}'
      : 'Сохранённый DNS: $primary${secondary.isEmpty ? '' : ' / $secondary'}';
  static String status(DnsDiagnosticState state) => switch (state.phase) {
    DnsDiagnosticPhase.idle => title,
    DnsDiagnosticPhase.running =>
      en
          ? 'Testing ${state.progress?.address ?? 'DNS'}… ${state.progress?.completed ?? 0}/${DnsDiagnosticService.measurements}'
          : 'Проверяю ${state.progress?.address ?? 'DNS'}… ${state.progress?.completed ?? 0}/${DnsDiagnosticService.measurements}',
    DnsDiagnosticPhase.cancelling => en ? 'Cancelling…' : 'Останавливаю…',
    DnsDiagnosticPhase.completed =>
      en
          ? 'Selected ${state.report!.selected!.pair.name}: ${state.report!.selected!.primary.address} / ${state.report!.selected!.secondary.address}. ${state.report!.selected!.dnsSuccesses}/6 valid DoT replies; median pair latency ${state.report!.selected!.latency.round()} ms. Both addresses are saved for the next TUN connection.'
          : 'Выбрана ${state.report!.selected!.pair.name}: ${state.report!.selected!.primary.address} / ${state.report!.selected!.secondary.address}. Корректных DoT-ответов: ${state.report!.selected!.dnsSuccesses}/6; средняя медианная задержка пары ${state.report!.selected!.latency.round()} мс. Оба адреса сохранены для следующего подключения TUN.',
    DnsDiagnosticPhase.noWorkingPair =>
      en
          ? 'No reliable encrypted DNS pair found. Your previous DNS is unchanged. ICMP or ordinary DNS alone does not prove DoT works; port 853 may be blocked.'
          : 'Надёжная зашифрованная пара не найдена. Прежний DNS не изменён. Один ICMP или обычный DNS не доказывает работу DoT; возможно, порт 853 заблокирован.',
    DnsDiagnosticPhase.cancelled =>
      en
          ? 'Cancelled. Your previous DNS is unchanged.'
          : 'Отменено. Прежний DNS не изменён.',
    DnsDiagnosticPhase.vpnActive =>
      en
          ? 'Turn VPN off before diagnostics. No DNS changes were applied.'
          : 'Перед диагностикой выключите VPN. DNS не изменён.',
    DnsDiagnosticPhase.settingsChanged =>
      en
          ? 'DNS was changed during diagnostics. Your newer setting was not overwritten.'
          : 'DNS изменился во время диагностики. Новый выбор не перезаписан.',
    DnsDiagnosticPhase.storageError =>
      en
          ? 'Could not save DNS. Check free disk space and permissions; the previous setting is unchanged.'
          : 'Не удалось сохранить DNS. Проверьте свободное место и права; прежняя настройка не изменена.',
    DnsDiagnosticPhase.failed =>
      en
          ? 'Diagnostics failed. Your previous DNS is unchanged.'
          : 'Диагностика не завершена. Прежний DNS не изменён.',
  };
}

class DnsDiagnosticSection extends ConsumerWidget {
  const DnsDiagnosticSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final busy = ref.watch(dnsDiagnosticControllerProvider).busy;
    final idle = ref.watch(connectionControllerProvider) is ConnectionIdle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(DnsDiagnosticStrings.title, style: PortText.large),
        const SizedBox(height: 6),
        Text(DnsDiagnosticStrings.help, style: PortText.muted),
        const SizedBox(height: 8),
        Text(
          DnsDiagnosticStrings.selected(
            settings.tunDnsServer,
            settings.tunDnsSecondaryServer,
          ),
          style: PortText.small,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: PortButton.outline(
            key: const ValueKey('dns-diagnostics'),
            leading: const Icon(LucideIcons.activity, size: 14),
            onPressed:
                busy || !idle || !ref.watch(dnsDiagnosticSupportedProvider)
                ? null
                : () => _confirm(context, ref),
            child: Text(DnsDiagnosticStrings.button),
          ),
        ),
        if (!idle) ...[
          const SizedBox(height: 6),
          Text(
            DnsDiagnosticStrings.status(
              const DnsDiagnosticState(phase: DnsDiagnosticPhase.vpnActive),
            ),
            style: PortText.muted,
          ),
        ],
      ],
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final confirmed = await showPortDialog<bool>(
      context: context,
      builder: (context) => PortDialog.alert(
        title: Text(DnsDiagnosticStrings.title),
        description: Text(DnsDiagnosticStrings.confirmation),
        actions: [
          PortButton.outline(
            key: const ValueKey('cancel-dns-consent'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(DnsDiagnosticStrings.cancel),
          ),
          PortButton(
            key: const ValueKey('confirm-dns-consent'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(DnsDiagnosticStrings.start),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await showPortDialog<void>(
      context: context,
      builder: (_) => const _DnsDiagnosticDialog(),
    );
  }
}

class _DnsDiagnosticDialog extends ConsumerStatefulWidget {
  const _DnsDiagnosticDialog();
  @override
  ConsumerState<_DnsDiagnosticDialog> createState() =>
      _DnsDiagnosticDialogState();
}

class _DnsDiagnosticDialogState extends ConsumerState<_DnsDiagnosticDialog> {
  late final DnsDiagnosticController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(dnsDiagnosticControllerProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_controller.start(confirmed: true));
    });
  }

  @override
  void dispose() {
    // Disposal may run during a widget-tree update. Cancel the owned work
    // immediately, without synchronously writing provider state in that phase.
    _controller.cancel(notify: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dnsDiagnosticControllerProvider);
    final results = state.report?.results ?? state.progress?.results ?? [];
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        // Navigator.pop completes before its reverse animation/dispose. Do
        // not allow a fast last probe to save DNS after the dialog was closed.
        if (didPop) _controller.cancel(notify: false);
      },
      child: PortDialog(
        title: Text(DnsDiagnosticStrings.title),
        description: Text(DnsDiagnosticStrings.status(state)),
        actions: [
          if (!state.busy)
            PortButton.outline(
              key: const ValueKey('close-dns-diagnostics'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(DnsDiagnosticStrings.close),
            ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.busy) ...[
              Align(
                alignment: Alignment.centerRight,
                child: PortButton.outline(
                  key: const ValueKey('cancel-dns-diagnostics'),
                  onPressed: state.phase == DnsDiagnosticPhase.cancelling
                      ? null
                      : _controller.cancel,
                  child: Text(DnsDiagnosticStrings.cancel),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                label: DnsDiagnosticStrings.title,
                value:
                    '${state.progress?.completed ?? 0}/${DnsDiagnosticService.measurements}',
                child: Container(
                  height: 6,
                  color: PortColors.secondary,
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor:
                        (state.progress?.completed ?? 0) /
                        DnsDiagnosticService.measurements,
                    child: ColoredBox(
                      color: PortColors.primary,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            for (final pair in diagnosticDnsPairs) ...[
              Text(pair.name, style: PortText.small),
              const SizedBox(height: 4),
              if (results.any((result) => identical(result.pair, pair)))
                for (final endpoint in [
                  results
                      .firstWhere((result) => identical(result.pair, pair))
                      .first,
                  results
                      .firstWhere((result) => identical(result.pair, pair))
                      .second,
                ])
                  Text(_endpointSummary(endpoint), style: PortText.muted)
              else
                Text(
                  '${pair.primary} / ${pair.secondary} · …',
                  style: PortText.muted,
                ),
              const SizedBox(height: 12),
            ],
            Text(
              DnsDiagnosticStrings.en
                  ? 'A short comparison on this network, not a DNSSEC, censorship or privacy certification. ICMP loss alone does not exclude a working encrypted resolver.'
                  : 'Короткое сравнение в текущей сети, не проверка DNSSEC, цензуры или гарантия приватности. Потери ICMP сами по себе не исключают рабочий зашифрованный DNS.',
              style: PortText.muted,
            ),
          ],
        ),
      ),
    );
  }

  String _endpointSummary(DnsEndpointResult endpoint) {
    final ping = DnsEndpointResult.medianLatency(endpoint.icmp);
    final losses = (3 - endpoint.icmp.whereType<int>().length) * 100 / 3;
    return '${endpoint.address}\n'
        'ICMP ${ping?.round() ?? '—'} ${DnsDiagnosticStrings.en ? 'ms' : 'мс'} · '
        '${DnsDiagnosticStrings.en ? 'loss' : 'потери'} ${losses.round()}% · '
        'DNS ${endpoint.udp.whereType<int>().length}/3 · '
        'DoT ${endpoint.dnsSuccesses}/3 '
        '(${endpoint.dnsLatency?.round() ?? '—'} ${DnsDiagnosticStrings.en ? 'ms' : 'мс'})';
  }
}
