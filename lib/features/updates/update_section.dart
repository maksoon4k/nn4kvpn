import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core_abstraction/app_settings_provider.dart';
import '../../widgets/port_ui/port_ui.dart';
import 'app_update_controller.dart';
import 'update_strings.dart';

class UpdateSection extends ConsumerStatefulWidget {
  const UpdateSection({super.key});

  @override
  ConsumerState<UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends ConsumerState<UpdateSection> {
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
        Text(UpdateStrings.publicAccess, style: PortText.muted),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
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
          onChanged: update.busy ? null : _setAutomatic,
        ),
        const SizedBox(height: 8),
        Text(UpdateStrings.automaticHelp, style: PortText.muted),
        const SizedBox(height: 12),
        Text(UpdateStrings.integrityHelp, style: PortText.muted),
        // Technical release bodies contain publisher/source URLs. Keep them
        // on the release page, not in the app's owner-neutral settings UI.
      ],
    );
  }

  String _status(AppUpdateState state) => switch (state.phase) {
    AppUpdatePhase.idle => '',
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
