import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../app/app_paths.dart';
import '../app/bounded_http.dart';
import '../core_abstraction/app_settings.dart';
import '../core_abstraction/geo_dat_format.dart';

String geoipFilePath() =>
    '${ensureFluxGeoDirectory()}${Platform.pathSeparator}geoip.dat';
String geositeFilePath() =>
    '${ensureFluxGeoDirectory()}${Platform.pathSeparator}geosite.dat';

const maxGeoAssetBytes = 64 * 1024 * 1024;

/// Докачивает отсутствующие базы и обновляет стандартные базы раз в неделю.
/// При сетевой ошибке приложение продолжает работать с локальными файлами.
Future<void> ensureGeoAssets({
  required String geoipUrl,
  required String geositeUrl,
  Directory? directory,
  http.Client? client,
}) async {
  final target = directory ?? fluxGeoDirectory();
  await target.create(recursive: true);
  await Future.wait([
    _ensureFile(
      '${target.path}/geoip.dat',
      geoipUrl,
      parseGeoIpDat,
      defaultGeoipUrl,
      client,
    ),
    _ensureFile(
      '${target.path}/geosite.dat',
      geositeUrl,
      parseGeoSiteDat,
      defaultGeositeUrl,
      client,
    ),
  ]);
}

/// Принудительно перекачивает оба файла (кнопка "Обновить" в настройках) —
/// в отличие от [ensureGeoAssets], не проверяет существование заранее.
/// Ошибка сети/HTTP/парсинга пробрасывается наружу, чтобы UI мог показать
/// тост с причиной — здесь это явное пользовательское действие, а не
/// best-effort фон при старте.
Future<void> forceUpdateGeoAssets({
  required String geoipUrl,
  required String geositeUrl,
  Directory? directory,
  http.Client? client,
}) async {
  final target = directory ?? fluxGeoDirectory();
  await target.create(recursive: true);
  await Future.wait([
    _downloadTo('${target.path}/geoip.dat', geoipUrl, parseGeoIpDat, client),
    _downloadTo(
      '${target.path}/geosite.dat',
      geositeUrl,
      parseGeoSiteDat,
      client,
    ),
  ]);
}

Future<void> _ensureFile(
  String path,
  String url,
  List<Object> Function(Uint8List) validate,
  String defaultUrl,
  http.Client? client,
) async {
  try {
    final stat = await File(path).stat();
    if (stat.type == FileSystemEntityType.file &&
        stat.size > 0 &&
        (url != defaultUrl ||
            DateTime.now().difference(stat.modified) <
                const Duration(days: 7))) {
      return;
    }
    await _downloadTo(path, url, validate, client);
  } catch (_) {
    // best-effort — см. doc-комментарий ensureGeoAssets
  }
}

/// Пишет во временный файл рядом и переименовывает поверх целевого —
/// обрыв соединения на середине скачивания не оставляет битый файл вместо
/// рабочего (старый, если был, остаётся нетронутым до успешного `rename`).
/// [validate] прогоняет скачанные байты через парсер из
/// `geo_dat_format.dart` перед заменой — битый/не тот формат файла не должен
/// молча стать новым "рабочим" geoip/geosite (ROADMAP.md, трек 20, п.11).
Future<void> _downloadTo(
  String path,
  String url,
  List<Object> Function(Uint8List) validate,
  http.Client? client,
) async {
  final response = await boundedHttpGet(
    Uri.parse(url),
    maxBytes: maxGeoAssetBytes,
    allowHttp: true,
    client: client,
  );
  if (response.statusCode != 200) {
    throw HttpException('HTTP ${response.statusCode} при скачивании geo-базы');
  }
  if (response.bodyBytes.isEmpty) {
    throw HttpException('Пустой ответ при скачивании geo-базы');
  }
  if (validate(response.bodyBytes).isEmpty) {
    throw const FormatException('Geo-база не содержит записей');
  }
  final staging = await Directory(
    File(path).parent.path,
  ).createTemp('.geo-download-');
  try {
    final tmp = File('${staging.path}${Platform.pathSeparator}data');
    await tmp.writeAsBytes(response.bodyBytes);
    await tmp.rename(path);
  } finally {
    await staging.delete(recursive: true);
  }
}
