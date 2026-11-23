import '../../core_abstraction/app_settings.dart';
import '../../l10n/app_locale.dart';
import 'github_release.dart';

/// Feature-local translations follow the same effective locale as S.
class UpdateStrings {
  static bool get _en => AppLocale.effective == AppLanguage.en;
  static String get title => _en ? 'Updates' : 'Обновления';
  static String get publicAccess => _en
      ? 'Updates are available to everyone — no account or token required.'
      : 'Обновления доступны всем — без аккаунта и токена.';
  static String get notConfigured => _en
      ? 'The update source is unavailable in this build.'
      : 'Источник обновлений недоступен в этой сборке.';
  static String get save => _en ? 'Save' : 'Сохранить';
  static String get cancel => _en ? 'Cancel' : 'Отмена';
  static String get check => _en ? 'Check for updates' : 'Проверить обновления';
  static String get checking =>
      _en ? 'Checking for updates…' : 'Проверяю обновления…';
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
      ? 'Only stable releases with a matching Windows installer and a verified SHA-256 digest are accepted. A checksum proves file integrity, not publisher or executable trust.'
      : 'Принимаются только стабильные релизы с Windows-установщиком и проверенной SHA-256. Контрольная сумма подтверждает целостность файла, но не добросовестность издателя или безопасность программы.';
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
          ? 'The update source in this build is invalid.'
          : 'Некорректный источник обновлений в этой сборке.',
    UpdateFailure.accessDenied =>
      _en
          ? 'The update server denied access. Try again later.'
          : 'Сервер обновлений отказал в доступе. Повторите позже.',
    UpdateFailure.noRelease =>
      _en
          ? 'No public Windows release was found.'
          : 'Публичный Windows-релиз не найден.',
    UpdateFailure.rateLimited =>
      _en
          ? 'The update server request limit was reached. Try again later.'
          : 'Исчерпан лимит запросов сервера обновлений. Повторите позже.',
    UpdateFailure.network =>
      _en
          ? 'Could not reach the update server or download the update.'
          : 'Не удалось связаться с сервером обновлений или скачать обновление.',
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
          ? 'The update server did not provide a SHA-256 digest. Installation is blocked.'
          : 'Сервер обновлений не предоставил SHA-256. Установка заблокирована.',
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
