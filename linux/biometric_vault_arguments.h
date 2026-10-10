#ifndef BIOMETRIC_VAULT_ARGUMENTS_H_
#define BIOMETRIC_VAULT_ARGUMENTS_H_

#include <flutter_linux/fl_value.h>
#include <cstring>

// Validate before calling typed FlValue getters or passing strings to
// libsecret. Missing authentication options must never opt into plain storage.
inline const gchar* biometric_vault_validate_arguments(const gchar* method,
                                                       FlValue* args) {
  const bool is_init = strcmp(method, "init") == 0;
  const bool is_write = strcmp(method, "write") == 0;
  if (!is_init && !is_write && strcmp(method, "read") != 0 &&
      strcmp(method, "delete") != 0) {
    return nullptr;
  }
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return "Argument map missing or malformed";
  }
  FlValue* name = fl_value_lookup_string(args, "name");
  if (name == nullptr || fl_value_get_type(name) != FL_VALUE_TYPE_STRING ||
      fl_value_get_string(name)[0] == '\0') {
    return "Storage name missing or malformed";
  }
  if (is_init) {
    FlValue* options = fl_value_lookup_string(args, "options");
    if (options == nullptr || fl_value_get_type(options) != FL_VALUE_TYPE_MAP) {
      return "Argument map missing or malformed";
    }
    FlValue* required = fl_value_lookup_string(options, "authenticationRequired");
    if (required == nullptr || fl_value_get_type(required) != FL_VALUE_TYPE_BOOL) {
      return "authenticationRequired must be a boolean";
    }
    if (fl_value_get_bool(required)) {
      return "Linux plugin only supports non-authenticated secure storage";
    }
  }
  if (is_write) {
    FlValue* content = fl_value_lookup_string(args, "content");
    if (content == nullptr || fl_value_get_type(content) != FL_VALUE_TYPE_STRING) {
      return "Storage content missing or malformed";
    }
  }
  return nullptr;
}

#endif  // BIOMETRIC_VAULT_ARGUMENTS_H_
