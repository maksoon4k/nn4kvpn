import 'dart:io';

import 'package:uuid/uuid.dart';

/// Owns only named copies inside its directory, never a path from settings
/// outside that directory. Shared by custom images and videos.
class ManagedBackgroundStorage {
  final Directory directory;
  final String prefix;

  const ManagedBackgroundStorage(this.directory, {required this.prefix});

  bool _ownedName(String name) => RegExp(
    '^${RegExp.escape(prefix)}(-[a-f0-9]{32})?(\\.[a-zA-Z0-9]{1,10})?\$',
  ).hasMatch(name);

  Future<String> import(String sourcePath) async {
    await directory.create(recursive: true);
    final source = File(sourcePath);
    final name = source.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    final extension = dot >= 0 ? name.substring(dot) : '';
    if (extension.isNotEmpty &&
        !RegExp(r'^\.[a-zA-Z0-9]{1,10}$').hasMatch(extension)) {
      throw const FileSystemException('Invalid background file extension');
    }
    // FileImage and video controllers identify their source by path. Never
    // overwrite a path that may still be cached, displayed or locked by MF.
    final revision = const Uuid().v4().replaceAll('-', '');
    final destinationName = '$prefix-$revision$extension';
    final destination = File('${directory.path}/$destinationName');
    final staging = await directory.createTemp('.background-import-');
    final temporary = File('${staging.path}/data$extension');
    try {
      // Copy before deleting anything, including when source is our old copy.
      await source.copy(temporary.path);
      await temporary.rename(destination.path);
      // The caller retires its previous copy ONLY after settings are saved.
      // Sweeping this directory could delete another import awaiting commit.
      return destination.path;
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
        await staging.delete();
      } catch (_) {
        // Keep the original import error, if any.
      }
    }
  }

  Future<void> delete(String path) async {
    final file = File(path);
    if (!await file.exists() || !await directory.exists()) return;
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return;
    }
    final root = await directory.resolveSymbolicLinks();
    final resolved = File(await file.resolveSymbolicLinks());
    var parent = resolved.parent.path;
    var expected = root;
    if (Platform.isWindows) {
      parent = parent.toLowerCase();
      expected = expected.toLowerCase();
    }
    if (parent != expected || !_ownedName(resolved.uri.pathSegments.last)) {
      return;
    }
    await resolved.delete();
  }
}
