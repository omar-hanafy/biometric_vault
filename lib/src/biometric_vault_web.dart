import 'dart:async';
import 'package:web/web.dart' as web show window;

import 'package:biometric_vault/src/biometric_vault.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'storage_name.dart';

/// A web implementation of the BiometricVault plugin.
class BiometricVaultPluginWeb extends BiometricVault {
  /// Creates the localStorage-backed implementation without authentication.
  BiometricVaultPluginWeb() : super.create();

  /// Prefix shared with the existing web storage namespace.
  static const namePrefix = 'io.github.omarhanafy.authpass.';

  /// Registers this implementation as the active web storage backend.
  static void registerWith(Registrar registrar) {
    BiometricVault.instance = BiometricVaultPluginWeb();
  }

  @override
  Future<CanAuthenticateResponse> canAuthenticate({
    StorageFileInitOptions? options,
  }) async => CanAuthenticateResponse.errorHwUnavailable;

  @override
  Future<BiometricVaultFile> getStorage(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
    PromptInfo promptInfo = PromptInfo.defaultValues,
  }) async {
    validateStorageName(name);
    return BiometricVaultFile(this, namePrefix + name, promptInfo);
  }

  @override
  Future<bool> delete(String name, PromptInfo promptInfo) async {
    return _storageOperation('DeleteError', () {
      final oldValue = web.window.localStorage.getItem(name);
      web.window.localStorage.removeItem(name);
      return oldValue != null;
    });
  }

  @override
  Future<bool> linuxCheckAppArmorError() async => false;

  @override
  Future<String?> read(String name, PromptInfo promptInfo) async {
    return _storageOperation(
      'ReadError',
      () => web.window.localStorage.getItem(name),
    );
  }

  @override
  Future<void> write(String name, String content, PromptInfo promptInfo) async {
    _storageOperation(
      'WriteError',
      () => web.window.localStorage.setItem(name, content),
    );
  }

  T _storageOperation<T>(String code, T Function() operation) {
    try {
      return operation();
    } catch (error) {
      throw BiometricVaultPluginException(
        code,
        'Browser storage operation failed. Storage may be disabled or its '
        'quota may have been exceeded.',
        error,
      );
    }
  }
}
