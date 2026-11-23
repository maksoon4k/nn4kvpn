import 'dart:convert';

import 'package:flutter/material.dart'
    show Colors, Material, TextField, InputDecoration, InputBorder;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core_abstraction/app_settings_provider.dart';
import '../../core_abstraction/tun_application_routing.dart';
import '../../widgets/port_ui/port_ui.dart';
import 'windows_process_catalog.dart';

class TunApplicationRoutingSection extends ConsumerWidget {
  const TunApplicationRoutingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(appSettingsProvider).tunApplicationRouting;
    void update(
      TunApplicationRouting Function(TunApplicationRouting) transform,
    ) {
      try {
        ref
            .read(appSettingsProvider.notifier)
            .update(
              (settings) => settings.copyWith(
                tunApplicationRouting: transform(
                  settings.tunApplicationRouting,
                ),
              ),
            );
      } catch (error) {
        PortToaster.of(context).show(
          PortToast.destructive(
            title: Text('Не удалось сохранить правила: $error'),
          ),
        );
      }
    }

    Future<void> editRule([TunApplicationRule? rule]) async {
      final edited = await showPortDialog<TunApplicationRule>(
        context: context,
        builder: (_) => _ApplicationRuleEditor(
          initial: rule,
          defaultAction: policy.suggestedAction,
        ),
      );
      if (edited == null || !context.mounted) return;
      update((current) {
        final rules = current.rules
            .where((r) => r.identity != rule?.identity)
            .toList();
        if (rules.any((r) => r.identity == edited.identity)) {
          throw const FormatException('Это приложение уже добавлено.');
        }
        return current.copyWith(rules: [...rules, edited]);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Приложения в TUN', style: PortText.h4),
        const SizedBox(height: 10),
        if (policy.validationError != null) ...[
          Text(
            'Конфигурация не применена. Исправьте JSON: ${policy.validationError}',
            style: PortText.small.copyWith(color: PortColors.destructive),
          ),
          const SizedBox(height: 8),
        ],
        PortSwitch(
          key: const ValueKey('tun-app-routing-enabled'),
          value: policy.enabled,
          label: const Text('Маршрутизация по приложениям'),
          onChanged: policy.validationError != null
              ? null
              : (enabled) => update((p) => p.copyWith(enabled: enabled)),
        ),
        const SizedBox(height: 12),
        PortSelect<TunApplicationRoutingMode>(
          key: ValueKey('tun-app-mode-${policy.mode.name}'),
          initialValue: policy.mode,
          options: const [
            PortSelectOption(
              value: TunApplicationRoutingMode.whitelist,
              child: Text('Белый список'),
            ),
            PortSelectOption(
              value: TunApplicationRoutingMode.blacklist,
              child: Text('Чёрный список'),
            ),
          ],
          selectedOptionBuilder: (_, value) => Text(
            value == TunApplicationRoutingMode.whitelist
                ? 'Белый список'
                : 'Чёрный список',
          ),
          onChanged: (mode) {
            if (mode != null && policy.validationError == null) {
              update((p) => p.copyWith(mode: mode));
            }
          },
        ),
        const SizedBox(height: 8),
        Text(
          policy.mode == TunApplicationRoutingMode.whitelist
              ? 'Белый список: выбранным приложениям назначается действие; остальные — direct (напрямую).'
              : 'Чёрный список: выбранным приложениям назначается действие; остальные — proxy (через VPN).',
          style: PortText.muted,
        ),
        const SizedBox(height: 6),
        Text(
          'direct — напрямую · proxy — через VPN · block — запрет соединений. '
          'При включении этот режим заменяет доменные/IP-пресеты только в TUN. '
          'Точный путь приоритетнее имени .exe. DNS и служебные исключения VPN сохраняются. '
          'Неопределённый процесс следует правилу для остальных. Изменения активного TUN вызывают переподключение.',
          style: PortText.muted,
        ),
        const SizedBox(height: 12),
        for (final rule in policy.rules)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PortSwitch(
                  key: ValueKey('tun-app-rule-${rule.identity}'),
                  value: rule.enabled,
                  label: Text(
                    rule.value,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    style: PortText.small,
                  ),
                  onChanged: (enabled) => update(
                    (p) => p.copyWith(
                      rules: [
                        for (final r in p.rules)
                          r.identity == rule.identity
                              ? r.copyWith(enabled: enabled)
                              : r,
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: PortSelect<TunApplicationAction>(
                        key: ValueKey('${rule.identity}-${rule.action.name}'),
                        initialValue: rule.action,
                        options: [
                          for (final action in TunApplicationAction.values)
                            PortSelectOption(
                              value: action,
                              child: Text(action.name),
                            ),
                        ],
                        selectedOptionBuilder: (_, action) => Text(action.name),
                        onChanged: (action) {
                          if (action != null) {
                            update(
                              (p) => p.copyWith(
                                rules: [
                                  for (final r in p.rules)
                                    r.identity == rule.identity
                                        ? r.copyWith(action: action)
                                        : r,
                                ],
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    PortIconButton.ghost(
                      key: ValueKey('tun-app-edit-${rule.identity}'),
                      icon: const Icon(LucideIcons.pencil, size: 15),
                      onPressed: () => editRule(rule),
                    ),
                    PortIconButton.ghost(
                      key: ValueKey('tun-app-delete-${rule.identity}'),
                      icon: const Icon(LucideIcons.trash2, size: 15),
                      onPressed: () => update(
                        (p) => p.copyWith(
                          rules: p.rules
                              .where((r) => r.identity != rule.identity)
                              .toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PortButton.outline(
              key: const ValueKey('tun-app-processes'),
              leading: const Icon(LucideIcons.list, size: 16),
              onPressed: policy.validationError != null
                  ? null
                  : () => showPortDialog<void>(
                      context: context,
                      builder: (_) => const _ProcessPicker(),
                    ),
              child: const Text('Процессы'),
            ),
            PortButton.outline(
              key: const ValueKey('tun-app-add'),
              leading: const Icon(LucideIcons.plus, size: 16),
              onPressed: policy.validationError != null
                  ? null
                  : () => editRule(),
              child: const Text('Добавить вручную'),
            ),
            PortButton.outline(
              key: const ValueKey('tun-app-json'),
              leading: const Icon(LucideIcons.fileCode, size: 16),
              onPressed: () => showPortDialog<void>(
                context: context,
                builder: (_) => const _ApplicationJsonEditor(),
              ),
              child: const Text('Редактировать JSON'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Правила сохраняются в settings.json → tunApplicationRouting. Приложение можно добавить до его запуска.',
          style: PortText.muted,
        ),
      ],
    );
  }
}

class _ApplicationRuleEditor extends StatefulWidget {
  final TunApplicationRule? initial;
  final TunApplicationAction defaultAction;
  const _ApplicationRuleEditor({this.initial, required this.defaultAction});
  @override
  State<_ApplicationRuleEditor> createState() => _ApplicationRuleEditorState();
}

class _ApplicationRuleEditorState extends State<_ApplicationRuleEditor> {
  late final _target = TextEditingController(text: widget.initial?.value ?? '');
  late var _match = widget.initial?.match ?? TunApplicationMatch.processName;
  late var _action = widget.initial?.action ?? widget.defaultAction;
  String? _error;
  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final rule = TunApplicationRule.fromJson({
        _match.name: _target.text,
        'action': _action.name,
        'enabled': widget.initial?.enabled ?? true,
      });
      Navigator.of(context).pop(rule);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => PortDialog(
    title: Text(
      widget.initial == null ? 'Добавить приложение' : 'Изменить приложение',
    ),
    description: const Text(
      'Не обязательно запускать приложение. Укажите имя .exe или точный путь.',
    ),
    actions: [
      PortButton.outline(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Отмена'),
      ),
      PortButton(
        key: const ValueKey('tun-app-rule-save'),
        onPressed: _save,
        child: const Text('Сохранить'),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PortSelect<TunApplicationMatch>(
          key: const ValueKey('tun-app-rule-match'),
          initialValue: _match,
          options: const [
            PortSelectOption(
              value: TunApplicationMatch.processName,
              child: Text('Имя .exe'),
            ),
            PortSelectOption(
              value: TunApplicationMatch.processPath,
              child: Text('Полный путь'),
            ),
          ],
          selectedOptionBuilder: (_, m) => Text(
            m == TunApplicationMatch.processName ? 'Имя .exe' : 'Полный путь',
          ),
          onChanged: (m) {
            if (m != null) setState(() => _match = m);
          },
        ),
        const SizedBox(height: 8),
        PortInput(
          key: const ValueKey('tun-app-target'),
          controller: _target,
          autofocus: true,
          placeholder: _match == TunApplicationMatch.processName
              ? 'chrome.exe'
              : r'D:\Apps\example.exe',
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
        PortSelect<TunApplicationAction>(
          key: const ValueKey('tun-app-rule-action'),
          initialValue: _action,
          options: [
            for (final action in TunApplicationAction.values)
              PortSelectOption(value: action, child: Text(action.name)),
          ],
          selectedOptionBuilder: (_, action) => Text(action.name),
          onChanged: (action) {
            if (action != null) setState(() => _action = action);
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: PortText.small.copyWith(color: PortColors.destructive),
          ),
        ],
      ],
    ),
  );
}

class _ProcessPicker extends ConsumerStatefulWidget {
  const _ProcessPicker();
  @override
  ConsumerState<_ProcessPicker> createState() => _ProcessPickerState();
}

class _ProcessPickerState extends ConsumerState<_ProcessPicker> {
  List<RunningApplication>? _applications;
  String? _error;
  bool _loading = false;
  final _filter = TextEditingController();
  @override
  void initState() {
    super.initState();
    _filter.addListener(_filterChanged);
    _refresh();
  }

  void _filterChanged() => setState(() {});
  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final applications = await ref
          .read(applicationProcessSourceProvider)
          .list();
      if (mounted) setState(() => _applications = applications);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Не удалось прочитать процессы: $error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(RunningApplication app, bool selected) {
    try {
      ref.read(appSettingsProvider.notifier).update((settings) {
        final policy = settings.tunApplicationRouting;
        final identity = TunApplicationRule(
          match: TunApplicationMatch.processName,
          value: app.name,
          action: policy.suggestedAction,
        ).identity;
        final existing = policy.rules
            .where((r) => r.identity == identity)
            .firstOrNull;
        final rule =
            existing?.copyWith(enabled: selected) ??
            TunApplicationRule.fromJson({
              'processName': app.name,
              'action': policy.suggestedAction.name,
              'enabled': selected,
            });
        return settings.copyWith(
          tunApplicationRouting: policy.copyWith(
            rules: [...policy.rules.where((r) => r.identity != identity), rule],
          ),
        );
      });
    } catch (error) {
      setState(() => _error = 'Не удалось сохранить выбор: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = ref.watch(appSettingsProvider).tunApplicationRouting;
    final query = _filter.text.trim().toLowerCase();
    final applications =
        _applications
            ?.where((app) => app.name.toLowerCase().contains(query))
            .toList() ??
        [];
    return PortDialog(
      maxWidth: 600,
      title: const Text('Запущенные приложения'),
      description: const Text(
        'Снимок процессов только для выбора. Выбор сохраняется сразу и остаётся после закрытия приложения; PID не сохраняется.',
      ),
      actions: [
        PortButton.outline(
          onPressed: _loading ? null : _refresh,
          child: const Text('Обновить'),
        ),
        PortButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Готово'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PortInput(
            key: const ValueKey('tun-app-process-filter'),
            controller: _filter,
            placeholder: 'Поиск по имени .exe',
          ),
          const SizedBox(height: 8),
          if (_loading) Text('Чтение процессов…', style: PortText.muted),
          if (_error != null)
            Text(
              _error!,
              style: PortText.small.copyWith(color: PortColors.destructive),
            ),
          if (!_loading && _applications != null && applications.isEmpty)
            Text(
              'Ничего не найдено. Используйте «Добавить вручную».',
              style: PortText.muted,
            ),
          for (final app in applications)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: PortSwitch(
                key: ValueKey('tun-app-process-${app.name.toLowerCase()}'),
                value: policy.rules.any(
                  (r) =>
                      r.enabled &&
                      r.match == TunApplicationMatch.processName &&
                      r.value.toLowerCase() == app.name.toLowerCase(),
                ),
                label: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${app.name} · ${app.processCount}',
                      style: PortText.small,
                    ),
                    Text(
                      app.paths.join('\n'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: PortText.muted,
                    ),
                  ],
                ),
                onChanged: (selected) => _select(app, selected),
              ),
            ),
        ],
      ),
    );
  }
}

class _ApplicationJsonEditor extends ConsumerStatefulWidget {
  const _ApplicationJsonEditor();
  @override
  ConsumerState<_ApplicationJsonEditor> createState() =>
      _ApplicationJsonEditorState();
}

class _ApplicationJsonEditorState
    extends ConsumerState<_ApplicationJsonEditor> {
  late final _initial = ref.read(appSettingsProvider).tunApplicationRouting;
  late final _text = TextEditingController(
    text: const JsonEncoder.withIndent('  ').convert(_initial.toJson()),
  );
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    try {
      if (_text.text.length > 262144) {
        throw const FormatException('JSON не должен превышать 256 КБ.');
      }
      final policy = TunApplicationRouting.fromJson(jsonDecode(_text.text));
      ref.read(appSettingsProvider.notifier).update((settings) {
        if (settings.tunApplicationRouting != _initial) {
          throw const FormatException(
            'Правила изменились, пока редактор был открыт. Закройте и откройте редактор заново.',
          );
        }
        return settings.copyWith(tunApplicationRouting: policy);
      });
      Navigator.of(context).pop();
    } catch (error) {
      setState(
        () => _error = error is FormatException
            ? error.message
            : 'Не удалось сохранить: $error',
      );
    }
  }

  @override
  Widget build(BuildContext context) => PortDialog(
    maxWidth: 760,
    title: const Text('Конфигурация приложений · JSON'),
    description: const Text(
      'mode: whitelist / blacklist. В rules укажите processName или processPath, action: direct / proxy / block и enabled. Ошибочный JSON не сохраняется.',
    ),
    actions: [
      PortButton.outline(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Отмена'),
      ),
      PortButton(
        key: const ValueKey('tun-app-json-save'),
        onPressed: _save,
        child: const Text('Сохранить'),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: TextField(
            key: const ValueKey('tun-app-json-text'),
            controller: _text,
            minLines: 8,
            maxLines: 16,
            keyboardType: TextInputType.multiline,
            style: PortText.small.copyWith(fontFamily: 'Consolas'),
            decoration: const InputDecoration(border: InputBorder.none),
          ),
        ),
        if (_error != null)
          Text(
            _error!,
            style: PortText.small.copyWith(color: PortColors.destructive),
          ),
      ],
    ),
  );
}
