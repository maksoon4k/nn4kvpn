import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'github_release.dart';

abstract interface class UpdateTokenStore {
  Future<String?> read(String repository);
  Future<void> write(String repository, String token);
  Future<void> delete(String repository);
}

/// Generic credentials are encrypted by Windows for the CURRENT USER.
/// Nothing is written to settings.json, git, environment variables or logs.
class WindowsUpdateTokenStore implements UpdateTokenStore {
  final String targetPrefix;

  const WindowsUpdateTokenStore({this.targetPrefix = 'NN4K/GitHubUpdates'});

  String _target(String repository) =>
      '$targetPrefix/${GitHubRepository.parse(repository).slug}';

  @override
  Future<String?> read(String repository) async {
    if (!Platform.isWindows) return null;
    final target = _target(repository).toNativeUtf16();
    final result = calloc<Pointer<_Credential>>();
    // Resolve the symbol before CredReadW: loading a DLL after a failed call
    // can overwrite the thread's last-error value (including ERROR_NOT_FOUND).
    final getLastError = _getLastError;
    try {
      if (_credRead(target, 1, 0, result) == 0) {
        if (getLastError() == 1168) return null; // ERROR_NOT_FOUND
        throw const UpdateException(UpdateFailure.credentials);
      }
      final credential = result.value.ref;
      if (credential.blobSize > 2560 || credential.blob == nullptr) {
        throw const UpdateException(UpdateFailure.credentials);
      }
      return utf8.decode(credential.blob.asTypedList(credential.blobSize));
    } on UpdateException {
      rethrow;
    } catch (_) {
      throw const UpdateException(UpdateFailure.credentials);
    } finally {
      if (result.value != nullptr) _credFree(result.value.cast());
      calloc.free(result);
      calloc.free(target);
    }
  }

  @override
  Future<void> write(String repository, String token) async {
    if (!Platform.isWindows) {
      throw const UpdateException(UpdateFailure.unsupportedPlatform);
    }
    final bytes = utf8.encode(token.trim());
    if (bytes.isEmpty ||
        bytes.length > 2560 ||
        bytes.any((byte) => byte < 0x21 || byte > 0x7e)) {
      throw const UpdateException(UpdateFailure.credentials);
    }
    final target = _target(repository).toNativeUtf16();
    final user = 'GitHub Releases (read-only)'.toNativeUtf16();
    final blob = calloc<Uint8>(bytes.length);
    final credential = calloc<_Credential>();
    try {
      blob.asTypedList(bytes.length).setAll(0, bytes);
      credential.ref
        ..type =
            1 // CRED_TYPE_GENERIC
        ..targetName = target
        ..userName = user
        ..blobSize = bytes.length
        ..blob = blob
        ..persist = 2; // CRED_PERSIST_LOCAL_MACHINE (still per-user)
      if (_credWrite(credential, 0) == 0) {
        throw const UpdateException(UpdateFailure.credentials);
      }
    } finally {
      blob.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
      calloc.free(credential);
      calloc.free(blob);
      calloc.free(user);
      calloc.free(target);
    }
  }

  @override
  Future<void> delete(String repository) async {
    if (!Platform.isWindows) return;
    final target = _target(repository).toNativeUtf16();
    final getLastError = _getLastError;
    try {
      if (_credDelete(target, 1, 0) == 0 && getLastError() != 1168) {
        throw const UpdateException(UpdateFailure.credentials);
      }
    } finally {
      calloc.free(target);
    }
  }
}

// Native CREDENTIALW layout. Using existing ffi rather than adding a plugin
// keeps this Windows-only feature independent of Android/macOS implementations.
final class _Credential extends Struct {
  @Uint32()
  external int flags;
  @Uint32()
  external int type;
  external Pointer<Utf16> targetName;
  external Pointer<Utf16> comment;
  @Uint32()
  external int lastWrittenLow;
  @Uint32()
  external int lastWrittenHigh;
  @Uint32()
  external int blobSize;
  external Pointer<Uint8> blob;
  @Uint32()
  external int persist;
  @Uint32()
  external int attributeCount;
  external Pointer<Void> attributes;
  external Pointer<Utf16> targetAlias;
  external Pointer<Utf16> userName;
}

final _advapi = DynamicLibrary.open('advapi32.dll');
final _credRead = _advapi
    .lookupFunction<
      Int32 Function(
        Pointer<Utf16>,
        Uint32,
        Uint32,
        Pointer<Pointer<_Credential>>,
      ),
      int Function(Pointer<Utf16>, int, int, Pointer<Pointer<_Credential>>)
    >('CredReadW');
final _credWrite = _advapi
    .lookupFunction<
      Int32 Function(Pointer<_Credential>, Uint32),
      int Function(Pointer<_Credential>, int)
    >('CredWriteW');
final _credDelete = _advapi
    .lookupFunction<
      Int32 Function(Pointer<Utf16>, Uint32, Uint32),
      int Function(Pointer<Utf16>, int, int)
    >('CredDeleteW');
final _credFree = _advapi
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'CredFree',
    );
final _getLastError = DynamicLibrary.open(
  'kernel32.dll',
).lookupFunction<Uint32 Function(), int Function()>('GetLastError');
