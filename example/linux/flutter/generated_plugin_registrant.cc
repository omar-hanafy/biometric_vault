//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <biometric_vault/biometric_vault_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) biometric_vault_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "BiometricVaultPlugin");
  biometric_vault_plugin_register_with_registrar(biometric_vault_registrar);
}
