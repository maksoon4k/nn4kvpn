import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../app/external_web.dart';
import '../../../widgets/port_ui/port_ui.dart';

Uri youtubeAddress(String input) {
  final text = input.trim();
  if (text.isEmpty) return Uri.https('www.youtube.com', '/');
  if (text.length > 8192 || RegExp(r'[\x00-\x1f\\]').hasMatch(text)) {
    throw const FormatException('Слишком длинная или некорректная ссылка.');
  }
  final looksLikeUrl =
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(text) ||
      RegExp(
        r'^(?:www\.|m\.|music\.)?youtube\.com(?:/|$)|^youtu\.be(?:/|$)',
        caseSensitive: false,
      ).hasMatch(text);
  if (!looksLikeUrl) {
    return Uri.https('www.youtube.com', '/results', {'search_query': text});
  }
  final uri = Uri.parse(text.contains('://') ? text : 'https://$text');
  final host = uri.host.toLowerCase();
  if (uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      !(host == 'youtube.com' ||
          host.endsWith('.youtube.com') ||
          host == 'youtu.be')) {
    throw const FormatException(
      'Разрешены только HTTPS-ссылки youtube.com и youtu.be.',
    );
  }
  return uri;
}

class YoutubeTool extends StatefulWidget {
  final ExternalWebOpener openBrowser;
  const YoutubeTool({super.key, this.openBrowser = openExternalWeb});
  @override
  State<YoutubeTool> createState() => _YoutubeToolState();
}

class _YoutubeToolState extends State<YoutubeTool> {
  final _input = TextEditingController();
  bool _opening = false;
  String? _status;
  @override
  void initState() {
    super.initState();
    // Selecting YouTube in the tools menu is already the user's open action.
    _open('');
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _open(String input) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _status = null;
    });
    try {
      final uri = youtubeAddress(input);
      final opened = await widget.openBrowser(uri);
      if (!mounted) return;
      setState(
        () => _status = opened
            ? 'YouTube открыт в браузере.'
            : 'Браузер не открылся. Скопируйте ссылку и откройте её вручную.',
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _status = error is FormatException
              ? error.message
              : 'Не удалось открыть браузер: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _copy() async {
    try {
      final uri = youtubeAddress(_input.text);
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      if (mounted) setState(() => _status = 'Ссылка скопирована.');
    } catch (error) {
      if (mounted) {
        setState(
          () => _status = error is FormatException
              ? error.message
              : 'Не удалось скопировать ссылку: $error',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Настоящий YouTube, а не офлайн-пародия.', style: PortText.p),
      const SizedBox(height: 8),
      Text(
        'Видео, звук, вход в аккаунт и поиск работают на youtube.com в вашем браузере. '
        'Рекламу NN4K не блокирует. Доступность сайта зависит от соединения и правил для браузера.',
        style: PortText.muted,
      ),
      const SizedBox(height: 12),
      PortInput(
        key: const ValueKey('youtube-address'),
        controller: _input,
        placeholder: 'Поиск или ссылка на видео YouTube',
        onSubmitted: _open,
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          PortButton(
            key: const ValueKey('youtube-open'),
            onPressed: _opening ? null : () => _open(_input.text),
            child: Text(_opening ? 'Открытие…' : 'Открыть / Найти'),
          ),
          PortButton.outline(
            key: const ValueKey('youtube-home'),
            onPressed: _opening ? null : () => _open(''),
            child: const Text('Главная YouTube'),
          ),
          PortButton.outline(
            key: const ValueKey('youtube-copy'),
            onPressed: _copy,
            child: const Text('Скопировать ссылку'),
          ),
        ],
      ),
      if (_status != null) ...[
        const SizedBox(height: 10),
        Text(_status!, style: PortText.small),
      ],
    ],
  );
}
