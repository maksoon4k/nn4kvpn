import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core_abstraction/app_settings_provider.dart';
import '../../widgets/port_ui/port_ui.dart';
import 'app_update_controller.dart';
import 'github_release.dart';
import 'update_strings.dart';

class UpdateSection extends ConsumerStatefulWidget {
  const UpdateSection({super.key});

  @override
  ConsumerState<UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends ConsumerState<UpdateSection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref.read(appUpdateControllerProvider.notifier).loadTokenStatus(),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final update = ref.watch(appUpdateControllerProvider);
    final controller = ref.read(appUpdateControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(UpdateStrings.title, style: PortText.large),
        const SizedBox(height: 8),
        Text(
          settings.updateRepository.isEmpty
              ? UpdateStrings.notConfigured
              : settings.updateRepository,
          style: PortText.small,
        ),
        const SizedBox(height: 6),
        Text(
          update.hasToken
              ? UpdateStrings.tokenSaved
              : UpdateStrings.tokenNotSaved,
          style: PortText.muted,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PortButton.outline(
              key: const ValueKey('configure-updates'),
              leading: const Icon(LucideIcons.settings, size: 14),
              onPressed: update.busy
                  ? null
                  : () => showPortDialog<void>(
                      context: context,
                      builder: (_) => const _UpdateConfigurationDialog(),
                    ),
              child: Text(UpdateStrings.configure),
            ),
            PortButton.outline(
              key: const ValueKey('check-updates'),
              leading: const Icon(LucideIcons.refreshCw, size: 14),
              onPressed: update.busy ? null : controller.check,
              child: Text(UpdateStrings.check),
            ),
            if (update.release != null && !update.hasDownloaded)
              PortButton.outline(
                key: const ValueKey('download-update'),
                leading: const Icon(LucideIcons.download, size: 14),
                onPressed: update.busy ? null : controller.download,
                child: Text(UpdateStrings.download),
              ),
            if (update.hasDownloaded)
              PortButton(
                key: const ValueKey('install-update'),
                leading: const Icon(LucideIcons.download, size: 14),
                onPressed: update.busy ? null : _install,
                child: Text(UpdateStrings.install),
              ),
          ],
        ),
        if (update.phase != AppUpdatePhase.idle) ...[
          const SizedBox(height: 12),
          Text(_status(update), style: PortText.small),
        ],
        if (update.phase == AppUpdatePhase.downloading) ...[
          const SizedBox(height: 8),
          Semantics(
            label: UpdateStrings.downloading,
            value: '${(update.progress * 100).round()}%',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 6,
                color: PortColors.secondary,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: update.progress.clamp(0.0, 1.0),
                  child: ColoredBox(
                    color: PortColors.primary,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        PortSwitch(
          value: settings.checkForUpdatesOnStartup,
          label: Text(UpdateStrings.backgroundChecks),
          onChanged: update.busy
              ? null
              : (value) => ref
                    .read(appSettingsProvider.notifier)
                    .update(
                      (settings) =>
                          settings.copyWith(checkForUpdatesOnStartup: value),
                    ),
        ),
        const SizedBox(height: 12),
        PortSwitch(
          key: const ValueKey('automatic-updates'),
          value: settings.autoInstallUpdates,
          label: Text(UpdateStrings.automatic),
          onChanged: update.busy || settings.updateRepository.isEmpty
              ? null
              : _setAutomatic,
        ),
        const SizedBox(height: 8),
        Text(UpdateStrings.automaticHelp, style: PortText.muted),
        const SizedBox(height: 12),
        Text(UpdateStrings.integrityHelp, style: PortText.muted),
        if (update.release?.notes.isNotEmpty ?? false) ...[
          const SizedBox(height: 16),
          Text(UpdateStrings.releaseNotes, style: PortText.small),
          const SizedBox(height: 6),
          // Plain text only: release notes cannot inject actionable links or UI.
          Text(update.release!.notes, style: PortText.muted),
        ],
      ],
    );
  }

  String _status(AppUpdateState state) => switch (state.phase) {
    AppUpdatePhase.idle => '',
    AppUpdatePhase.configuring => UpdateStrings.saving,
    AppUpdatePhase.checking => UpdateStrings.checking,
    AppUpdatePhase.upToDate => UpdateStrings.upToDate,
    AppUpdatePhase.available => UpdateStrings.available(
      '${state.release!.version}',
    ),
    AppUpdatePhase.downloading =>
      '${UpdateStrings.downloading} ${(state.progress * 100).round()}%',
    AppUpdatePhase.ready => UpdateStrings.ready,
    AppUpdatePhase.installing => UpdateStrings.installing,
    AppUpdatePhase.error => UpdateStrings.failure(state.failure!),
  };

  Future<void> _install() async {
    final confirmed = await showPortDialog<bool>(
      context: context,
      builder: (context) => PortDialog.alert(
        title: Text(UpdateStrings.install),
        description: Text(UpdateStrings.installConfirmation),
        actions: [
          PortButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(UpdateStrings.cancel),
          ),
          PortButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(UpdateStrings.installConfirm),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(appUpdateControllerProvider.notifier).install();
    }
  }

  Future<void> _setAutomatic(bool value) async {
    if (value) {
      final confirmed = await showPortDialog<bool>(
        context: context,
        builder: (context) => PortDialog.alert(
          title: Text(UpdateStrings.automatic),
          description: Text(UpdateStrings.automaticHelp),
          actions: [
            PortButton.outline(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(UpdateStrings.cancel),
            ),
            PortButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(UpdateStrings.save),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (!mounted) return;
    ref
        .read(appSettingsProvider.notifier)
        .update((settings) => settings.copyWith(autoInstallUpdates: value));
  }
}

class _UpdateConfigurationDialog extends ConsumerStatefulWidget {
  const _UpdateConfigurationDialog();

  @override
  ConsumerState<_UpdateConfigurationDialog> createState() =>
      _UpdateConfigurationDialogState();
}

class _UpdateConfigurationDialogState
    extends ConsumerState<_UpdateConfigurationDialog> {
  late final TextEditingController _repository;
  final _token = TextEditingController();
  bool _removeToken = false;
  bool _saving = false;
  UpdateFailure? _failure;

  @override
  void initState() {
    super.initState();
    _repository = TextEditingController(
      text: ref.read(appSettingsProvider).updateRepository,
    );
  }

  @override
  void dispose() {
    _token.clear();
    _token.dispose();
    _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PortDialog(
    title: Text(UpdateStrings.configure),
    actions: [
      PortButton.outline(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: Text(UpdateStrings.cancel),
      ),
      PortButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? '…' : UpdateStrings.save),
      ),
    ],
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(UpdateStrings.repository, style: PortText.small),
        const SizedBox(height: 6),
        PortInput(
          key: const ValueKey('update-repository'),
          controller: _repository,
          placeholder: 'owner/nn4kvpn',
          enabled: !_saving,
        ),
        const SizedBox(height: 12),
        Text(UpdateStrings.token, style: PortText.small),
        const SizedBox(height: 6),
        PortInput(
          key: const ValueKey('update-token'),
          controller: _token,
          obscureText: true,
          placeholder: UpdateStrings.tokenPlaceholder,
          enabled: !_saving && !_removeToken,
        ),
        const SizedBox(height: 12),
        PortSwitch(
          value: _removeToken,
          label: Text(UpdateStrings.removeToken),
          onChanged: _saving
              ? null
              : (value) => setState(() => _removeToken = value),
        ),
        const SizedBox(height: 12),
        Text(UpdateStrings.tokenHelp, style: PortText.muted),
        if (_failure != null) ...[
          const SizedBox(height: 12),
          Text(UpdateStrings.failure(_failure!), style: PortText.small),
        ],
      ],
    ),
  );

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      await ref
          .read(appUpdateControllerProvider.notifier)
          .configure(
            _repository.text,
            token: _token.text,
            removeToken: _removeToken,
          );
      _token.clear();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(
          () => _failure = error is UpdateException
              ? error.failure
              : UpdateFailure.storage,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
