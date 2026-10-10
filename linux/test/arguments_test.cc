#include "../biometric_vault_arguments.h"

#include <initializer_list>

static FlValue* named_args() {
  FlValue* args = fl_value_new_map();
  fl_value_set_string_take(args, "name", fl_value_new_string("vault"));
  return args;
}

static void test_missing_or_malformed_map() {
  g_autoptr(FlValue) value = fl_value_new_string("not a map");
  for (const gchar* method : {"init", "read", "write", "delete"}) {
    g_assert_nonnull(biometric_vault_validate_arguments(method, nullptr));
    g_assert_nonnull(biometric_vault_validate_arguments(method, value));
  }
}

static void test_missing_or_malformed_name() {
  g_autoptr(FlValue) args = fl_value_new_map();
  for (const gchar* method : {"read", "write", "delete", "init"}) {
    g_assert_nonnull(biometric_vault_validate_arguments(method, args));
    fl_value_set_string_take(args, "name", fl_value_new_int(42));
    g_assert_nonnull(biometric_vault_validate_arguments(method, args));
    fl_value_set_string_take(args, "name", fl_value_new_string(""));
    g_assert_nonnull(biometric_vault_validate_arguments(method, args));
  }
}

static void test_init_requires_explicit_non_authentication() {
  g_autoptr(FlValue) args = named_args();
  g_assert_nonnull(biometric_vault_validate_arguments("init", args));
  fl_value_set_string_take(args, "options", fl_value_new_string("invalid"));
  g_assert_nonnull(biometric_vault_validate_arguments("init", args));
  g_autoptr(FlValue) options = fl_value_new_map();
  fl_value_set_string(args, "options", options);
  g_assert_nonnull(biometric_vault_validate_arguments("init", args));
  fl_value_set_string_take(options, "authenticationRequired", fl_value_new_string("false"));
  g_assert_nonnull(biometric_vault_validate_arguments("init", args));
  fl_value_set_string_take(options, "authenticationRequired", fl_value_new_bool(true));
  g_assert_nonnull(biometric_vault_validate_arguments("init", args));
  fl_value_set_string_take(options, "authenticationRequired", fl_value_new_bool(false));
  g_assert_null(biometric_vault_validate_arguments("init", args));
}

static void test_write_requires_string_content() {
  g_autoptr(FlValue) args = named_args();
  g_assert_nonnull(biometric_vault_validate_arguments("write", args));
  fl_value_set_string_take(args, "content", fl_value_new_int(42));
  g_assert_nonnull(biometric_vault_validate_arguments("write", args));
  fl_value_set_string_take(args, "content", fl_value_new_string(""));
  g_assert_null(biometric_vault_validate_arguments("write", args));
  fl_value_set_string_take(args, "content", fl_value_new_string("secret"));
  g_assert_null(biometric_vault_validate_arguments("write", args));
}

static void test_valid_read_and_delete() {
  g_autoptr(FlValue) args = named_args();
  g_assert_null(biometric_vault_validate_arguments("read", args));
  g_assert_null(biometric_vault_validate_arguments("delete", args));
}

static void test_non_storage_methods_do_not_require_args() {
  g_assert_null(biometric_vault_validate_arguments("canAuthenticate", nullptr));
  g_assert_null(biometric_vault_validate_arguments("unknown", nullptr));
}

int main(int argc, char** argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/arguments/map", test_missing_or_malformed_map);
  g_test_add_func("/arguments/name", test_missing_or_malformed_name);
  g_test_add_func("/arguments/init", test_init_requires_explicit_non_authentication);
  g_test_add_func("/arguments/write", test_write_requires_string_content);
  g_test_add_func("/arguments/read-delete", test_valid_read_and_delete);
  g_test_add_func("/arguments/other-methods", test_non_storage_methods_do_not_require_args);
  return g_test_run();
}
