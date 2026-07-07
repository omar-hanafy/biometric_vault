import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import './biometric_vault.dart';

/// The Windows implementation of [BiometricVault].
///
/// Values are stored through the Windows Credential Manager
/// (`CredRead`/`CredWrite`), which encrypts them for the current OS user but
/// does NOT gate access behind Windows Hello or any other authentication;
/// [canAuthenticate] therefore reports
/// [CanAuthenticateResponse.errorHwUnavailable].
class Win32BiometricVaultPlugin extends BiometricVault {
  /// Creates the Windows implementation.
  Win32BiometricVaultPlugin() : super.create();

  /// Prefix applied to every credential name to keep the plugin's entries
  /// recognizable in the Windows Credential Manager UI.
  static const namePrefix = 'io.github.omarhanafy.authpass.';

  /// Registers this class as the default instance of [BiometricVault].
  static void registerWith() {
    BiometricVault.instance = Win32BiometricVaultPlugin();
  }

  @override
  Future<CanAuthenticateResponse> canAuthenticate({
    StorageFileInitOptions? options,
  }) async {
    return CanAuthenticateResponse.errorHwUnavailable;
  }

  @override
  Future<BiometricVaultFile> getStorage(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
    PromptInfo promptInfo = PromptInfo.defaultValues,
  }) async {
    return BiometricVaultFile(this, namePrefix + name, promptInfo);
  }

  @override
  Future<bool> linuxCheckAppArmorError() async => false;

  @override
  Future<bool> delete(String name, PromptInfo promptInfo) async {
    return using((arena) {
      final namePointer = name.toPcwstr(allocator: arena);
      final Win32Result(:value, :error) = CredDelete(
        namePointer,
        CRED_TYPE_GENERIC,
      );
      if (!value) {
        if (error == ERROR_NOT_FOUND) {
          return false;
        }
        throw BiometricVaultPluginException(
          'DeleteError',
          'Error deleting credential $name: $error',
          null,
        );
      }
      return true;
    });
  }

  @override
  Future<String?> read(String name, PromptInfo promptInfo) async {
    return using((arena) {
      final credPointer = arena<Pointer<CREDENTIAL>>();
      final namePointer = name.toPcwstr(allocator: arena);
      try {
        final result = CredRead(namePointer, CRED_TYPE_GENERIC, credPointer);
        if (!result.value) {
          final errorCode = result.error;
          if (errorCode == ERROR_NOT_FOUND) {
            return null;
          }
          throw BiometricVaultPluginException(
            'ReadError',
            'Error reading credential $name: $errorCode '
                '(${WindowsException(HRESULT_FROM_WIN32(errorCode))})',
            null,
          );
        }
        final cred = credPointer.value.ref;
        final blob = cred.CredentialBlob.asTypedList(cred.CredentialBlobSize);

        return utf8.decode(blob);
      } finally {
        if (!credPointer.value.isNull) {
          CredFree(credPointer.value);
        }
      }
    });
  }

  @override
  Future<void> write(String name, String content, PromptInfo promptInfo) async {
    using((arena) {
      final contentBytes = utf8.encode(content);
      final blob = contentBytes.isEmpty
          ? nullptr
          : contentBytes.toNative(allocator: arena);
      final namePointer = name.toPwstr(allocator: arena);
      final userNamePointer = 'flutter.biometric_vault'.toPwstr(
        allocator: arena,
      );

      final credential = arena<CREDENTIAL>()
        ..ref.Type = CRED_TYPE_GENERIC
        ..ref.TargetName = namePointer
        ..ref.Persist = CRED_PERSIST_LOCAL_MACHINE
        ..ref.UserName = userNamePointer
        ..ref.CredentialBlob = blob
        ..ref.CredentialBlobSize = contentBytes.length;
      final Win32Result(:value, :error) = CredWrite(credential, 0);
      if (!value) {
        throw BiometricVaultPluginException(
          'WriteError',
          'Error writing credential $name: $error',
          null,
        );
      }
    });
  }
}
