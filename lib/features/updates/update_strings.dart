import '../../core_abstraction/app_settings.dart';
import '../../l10n/app_locale.dart';
import 'github_release.dart';

/// Feature-local translations follow the same effective locale as S.
class UpdateStrings {
  static bool get _en => AppLocale.effective == AppLanguage.en;
  static String get title => _en ? 'Updates' : 'Обновления';
  static String get configure => _en ? 'Configure GitHub' : 'Настроить GitHub';
  static String get repository => _en ? 'Repository' : 'Репозиторий';
  static String get notConfigured =>
      _en ? 'Repository not configured' : 'Репозиторий не настроен';
  static String get token =>
      _en ? 'Read-only GitHub token' : 'Read-only токен GitHub';
  static String get tokenPlaceholder => _en
      ? 'Leave blank to keep the saved token'
      : 'Оставьте пустым, чтобы сохранить прежний токен';
  static String get tokenSaved => _en
      ? 'Private-release access: token saved in Windows'
      : 'Доступ к приватным релизам: токен сохранён в Windows';
  static String get tokenNotSaved => _en
      ? 'No token saved (public releases only)'
      : 'Токен не сохранён (только публичные релизы)';
  static String get tokenHelp => _en
      ? 'For a private repository, create a fine-grained personal access token in GitHub Settings → Developer settings. Select only this repository and Contents: Read-only. Never use your publishing token here. The token is stored in your Windows Credential Manager, not in the app settings or binary.'
      : 'Для приватного репозитория создайте fine-grained personal access token в GitHub Settings → Developer settings. Выберите только этот репозиторий и Contents: Read-only. Не используйте здесь токен для публикации. Токен хранится в Диспетчере учётных данных Windows, а не в настройках или сборке приложения.';
  static String get removeToken =>
      _en ? 'Delete saved token' : 'Удалить сохранённый токен';
  static String get save => _en ? 'Save' : 'Сохранить';
  static String get saving =>
      _en ? 'Saving update settings…' : 'Сохраняю настройки обновления…';
  static String get cancel => _en ? 'Cancel' : 'Отмена';
  static String get check => _en ? 'Check for updates' : 'Проверить обновления';
  static String get checking => _en ? 'Checking GitHub…' : 'Проверяю GitHub…';
  static String get upToDate =>
      _en ? 'You have the latest version' : 'Установлена последняя версия';
  static String available(String version) =>
      _en ? 'Version $version is available' : 'Доступна версия $version';
  static String get download => _en ? 'Download' : 'Скачать';
  static String get downloading =>
      _en ? 'Downloading update…' : 'Скачиваю обновление…';
  static String get ready => _en
      ? 'Download verified. Ready to install.'
      : 'Файл скачан и проверен. Можно устанавливать.';
  static String get install =>
      _en ? 'Install and restart' : 'Установить и перезапустить';
  static String get installConfirm => _en ? 'Install' : 'Установить';
  static String get installing =>
      _en ? 'Preparing installation…' : 'Подготавливаю установку…';
  static String get installConfirmation => _en
      ? 'The app will disconnect its VPN, close, install the verified update and restart. Your servers and settings will be preserved.'
      : 'Приложение отключит своё VPN-соединение, закроется, установит проверенное обновление и запустится снова. Серверы и настройки сохранятся.';
  static String get backgroundChecks => _en
      ? 'Check on startup and every 6 hours'
      : 'Проверять при запуске и каждые 6 часов';
  static String get automatic => _en
      ? 'Download and install automatically'
      : 'Скачивать и устанавливать автоматически';
  static String get automaticHelp => _en
      ? 'Opt-in only. The app restarts when VPN is off; installation is deferred during an active connection. Updating an elevated app is blocked: restart it without administrator privileges first.'
      : 'Только с вашего согласия. Приложение перезапустится, когда VPN выключен; при активном соединении установка откладывается. Обновление с повышенными правами заблокировано: сначала перезапустите приложение без прав администратора.';
  static String get integrityHelp => _en
      ? 'Only stable GitHub Releases with a matching Windows installer and GitHub SHA-256 digest are accepted. A checksum proves file integrity, not that the publisher or executable is trustworthy.'
      : 'Принимаются только стабильные GitHub Releases с Windows-установщиком и SHA-256 от GitHub. Контрольная сумма подтверждает целостность файла, но не добросовестность издателя или безопасность программы.';
  static String get releaseNotes =>
      _en ? 'Release notes' : 'Изменения в релизе';

  static String failure(UpdateFailure failure) => switch (failure) {
    UpdateFailure.busy =>
      _en
          ? 'Another update operation is already running.'
          : 'Другая операция обновления уже выполняется.',
    UpdateFailure.repositoryNotConfigured => notConfigured,
    UpdateFailure.invalidRepository =>
      _en
          ? 'Enter owner/repository or its HTTPS GitHub URL.'
          : 'Укажите owner/repository или HTTPS-ссылку на GitHub.',
    UpdateFailure.accessDenied =>
      _en
          ? 'GitHub access denied. Check token permissions and expiration.'
          : 'GitHub отказал в доступе. Проверьте права и срок действия токена.',
    UpdateFailure.noRelease =>
      _en
          ? 'No release found, or the private repository is not accessible with this token.'
          : 'Релиз не найден, либо токен не даёт доступа к приватному репозиторию.',
    UpdateFailure.rateLimited =>
      _en
          ? 'GitHub request limit reached. Try again later.'
          : 'Исчерпан лимит запросов GitHub. Повторите позже.',
    UpdateFailure.network =>
      _en
          ? 'Could not reach GitHub or download the update.'
          : 'Не удалось связаться с GitHub или скачать обновление.',
    UpdateFailure.invalidRelease =>
      _en
          ? 'The release or downloaded file has an unexpected format.'
          : 'Некорректный формат релиза или скачанного файла.',
    UpdateFailure.missingInstaller =>
      _en
          ? 'This release has no matching NN4K Windows installer.'
          : 'В релизе нет подходящего Windows-установщика NN4K.',
    UpdateFailure.missingChecksum =>
      _en
          ? 'GitHub did not provide a SHA-256 digest. Installation is blocked.'
          : 'GitHub не предоставил SHA-256. Установка заблокирована.',
    UpdateFailure.checksumMismatch =>
      _en
          ? 'SHA-256 mismatch. The file will not be executed.'
          : 'SHA-256 не совпадает. Файл не будет запущен.',
    UpdateFailure.unexpectedSize =>
      _en
          ? 'The download is incomplete or its size is invalid.'
          : 'Файл скачан не полностью или имеет недопустимый размер.',
    UpdateFailure.insecureRedirect =>
      _en
          ? 'An untrusted download redirect was blocked.'
          : 'Перенаправление на недоверенный адрес заблокировано.',
    UpdateFailure.storage =>
      _en
          ? 'Could not read or write the update file. Check free space and permissions.'
          : 'Не удалось прочитать или записать обновление. Проверьте свободное место и права.',
    UpdateFailure.credentials =>
      _en
          ? 'Could not access Windows Credential Manager or save this token.'
          : 'Не удалось обратиться к Диспетчеру учётных данных Windows или сохранить токен.',
    UpdateFailure.elevated =>
      _en
          ? 'Restart NN4K without administrator privileges to install updates.'
          : 'Для обновления перезапустите NN4K без прав администратора.',
    UpdateFailure.unsupportedPlatform =>
      _en
          ? 'In-app installation is supported only on Windows.'
          : 'Установка из приложения поддерживается только в Windows.',
    UpdateFailure.installFailed =>
      _en
          ? 'Could not start the installer. The app has not been closed.'
          : 'Не удалось запустить установщик. Приложение не закрыто.',
  };
}
