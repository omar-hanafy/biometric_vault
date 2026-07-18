# Working on biometric_vault (maintainers)

Flutter plugin: encrypted secret storage gated by biometric/device-credential
authentication. Android (Keystore + BiometricPrompt), iOS/macOS (Keychain +
LocalAuthentication), Linux (libsecret), Windows (Credential Manager via Dart
FFI), web (localStorage fallback, not secure).

## Validation commands

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
dart tool/validate_agent_plugin.dart   # agent plugin tree + version sync
flutter test && (cd example && flutter test)
dart pub publish --dry-run
```

CI additionally requires a FULL pana score (any lost point fails) and builds
the example for android/ios/linux/web/windows. For runtime verification on a
simulator and the native test suites, use the repo skill
`.claude/skills/verify/SKILL.md`.

## Frozen compatibility contracts - never change without a migration design

- Method channel `biometric_vault`; method names `init`/`dispose`/`read`/
  `write`/`delete`/`canAuthenticate`/`biometryType`/`authenticate`; option and
  prompt JSON keys; error code strings (`AuthError:<Name>`,
  `StorageError:KeyInvalidated`, `StorageError:CorruptedData`); enum wire
  names in `CanAuthenticateResponse`/`BiometryType` (Kotlin constant names are
  the wire format).
- Persistence: Android files `<filesDir>/biometric_vault/<name>.v2.txt` /
  `.v3.txt`, Keystore aliases `_CM_<name>_master_key` (AES) and
  `_EM_<name>_master_key` (RSA envelope), payload layouts v2/v3; Darwin
  keychain service `flutter_biometric_vault`; Linux/Windows/web name prefix
  `io.github.omarhanafy.authpass`.
- New native enum constants require the Dart-side mapping FIRST (unknown wire
  values throw on Dart for `canAuthenticate`, map to `unknown` for
  `biometryType`).

## Source layout rules

- `ios/.../BiometricVaultImpl.swift` is a SYMLINK to
  `macos/biometric_vault/Sources/biometric_vault/BiometricVaultImpl.swift`.
  Edit the macos file only; never replace the symlink with a copy.
- Public API lives in `lib/src/biometric_vault.dart`; every public member is
  documented (pana requires it).

## Releases

- Lane: branch `release/x.y.z` -> PR to `main` (stable) or `dev` (`-dev.N`
  prerelease only). Bump `pubspec.yaml` and `CHANGELOG.md` together in the PR.
- Merging a pubspec change auto-creates tag `biometric_vault-v<version>`,
  which triggers pub.dev publishing via Trusted Publisher OIDC. Never create
  or move release tags manually; never reuse a published version.

## Agent plugin (Claude Code + OpenAI Codex)

- One dual-manifest plugin at `agent_plugin/biometric-vault/` (shared
  `skills/`, `.claude-plugin/plugin.json` + `.codex-plugin/plugin.json`);
  catalogs at `.claude-plugin/marketplace.json` (Claude) and
  `.agents/plugins/marketplace.json` (Codex).
- Plugin manifests and marketplace entries must carry the exact pubspec
  version; `dart tool/validate_agent_plugin.dart` enforces this and the
  self-containment rules (no `../` escapes, no absolute paths, strict
  single-line `key: value` SKILL.md frontmatter).
- The plugin tree is excluded from the pub.dev archive via `.pubignore`
  (installed from the Git repo instead); keep it that way.
- When a release changes public behavior, update the affected skills and
  references in the same PR. A future breaking release (2.0.0 or a storage
  format change) MUST add a dedicated `migrate-v1-to-v2`-style skill next to
  the existing ones before it ships.
