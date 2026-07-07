import 'dart:async';
import 'package:web/web.dart' as web show window;

import 'package:biometric_vault/src/biometric_vault.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// A web implementation of the BiometricVault plugin.
class BiometricVaultPluginWeb extends BiometricVault {
  BiometricVaultPluginWeb() : super.create();

  static const namePrefix = 'io.github.omarhanafy.authpass.';

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
    return BiometricVaultFile(this, namePrefix + name, promptInfo);
  }

  @override
  Future<bool> delete(String name, PromptInfo promptInfo) async {
    final oldValue = web.window.localStorage.getItem(name);
    web.window.localStorage.removeItem(name);
    return oldValue != null;
  }

  @override
  Future<bool> linuxCheckAppArmorError() async => false;

  @override
  Future<String?> read(String name, PromptInfo promptInfo) async {
    return web.window.localStorage.getItem(name);
  }

  @override
  Future<void> write(String name, String content, PromptInfo promptInfo) async {
    web.window.localStorage.setItem(name, content);
  }
}
