cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "biometric_vault")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "${PROJECT_NAME}_plugin")

add_library(${PLUGIN_NAME} SHARED
  "${PLUGIN_NAME}.cc"
)

find_package(PkgConfig REQUIRED)
pkg_check_modules (LIBSECRET REQUIRED IMPORTED_TARGET libsecret-1>=0.18)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_include_directories(${PLUGIN_NAME} PRIVATE ${LIBSECRET_INCLUDE_DIRS})
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::LIBSECRET)

# Opt in when verifying the plugin's channel argument validation. These tests
# need neither a running Flutter application nor an unlocked secret service.
option(BIOMETRIC_VAULT_BUILD_TESTS "Build biometric_vault native tests" OFF)
if(BIOMETRIC_VAULT_BUILD_TESTS)
  add_executable(biometric_vault_linux_tests "test/arguments_test.cc")
  apply_standard_settings(biometric_vault_linux_tests)
  target_compile_definitions(biometric_vault_linux_tests PRIVATE
    FLUTTER_LINUX_COMPILATION)
  set_target_properties(biometric_vault_linux_tests PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/biometric_vault_tests")
  target_link_libraries(biometric_vault_linux_tests PRIVATE flutter PkgConfig::GTK)
endif()

# List of absolute paths to libraries that should be bundled with the plugin
set(biometric_vault_bundled_libraries
  ""
  PARENT_SCOPE
)
