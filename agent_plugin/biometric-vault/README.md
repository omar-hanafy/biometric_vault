# Biometric Vault agent plugin

Package-specific skills that make AI coding agents (Claude Code and OpenAI
Codex) reliable when working with the
[`biometric_vault`](https://pub.dev/packages/biometric_vault) Flutter
package. The skills encode what generic agents routinely get wrong: the
per-platform host-app requirements, the sealed error contract and its
recovery rules, the supported test seam, and the data-safety rules for
migrating off `biometric_storage`.

This plugin is distributed from the Git repository (not the pub.dev
archive). It contains only markdown skills, reference documents, and one
copyable Dart test fake - **no hooks, no MCP servers, no scripts that run
automatically**.

## Skills

| Skill | Use it when |
|---|---|
| `integrate-biometric-vault` | Adding the package to an app: storage design, `StorageFileInitOptions` choice, Android/iOS/macOS/Linux/Windows/web setup, capability gating, exhaustive error handling |
| `troubleshoot-biometric-vault` | Runtime failures: `AuthException` codes (`failedToStart`, `lockedOut`, ...), `StorageInvalidatedException` after enrollment changes, macOS `-34018`, silent-writes stores where writes work but reads fail, simulator oddities |
| `test-with-biometric-vault` | Writing `flutter test`-runnable tests for app code that uses the vault, with a ready in-memory `FakeBiometricVault` (no channel mocks, no device) |
| `migrate-from-biometric-storage` | Converting an app from the `biometric_storage` package without losing users' stored secrets (the two packages cannot read each other's data) |

Skills activate automatically when a task matches their description; they
can also be invoked explicitly (below).

## Install: Claude Code

```
/plugin marketplace add omar-hanafy/biometric_vault
/plugin install biometric-vault@biometric-vault
```

(or from a shell: `claude plugin marketplace add omar-hanafy/biometric_vault`
then `claude plugin install biometric-vault@biometric-vault`). In an
already-running session, `/reload-plugins` picks the plugin up; new sessions
see it automatically. Explicit invocation:
`/biometric-vault:integrate-biometric-vault` (same pattern for the other
skills). Works in Claude Code CLI and the desktop app.

Update later with `/plugin marketplace update biometric-vault` followed by
`/plugin update biometric-vault`; remove with
`/plugin uninstall biometric-vault@biometric-vault`.

## Install: OpenAI Codex

```
codex plugin marketplace add omar-hanafy/biometric_vault
codex plugin add biometric-vault@biometric-vault
```

Start a new Codex session afterwards so the skills are listed. Explicit
invocation: mention `$integrate-biometric-vault` (same pattern for the other
skills), or browse `/skills`. Plugins work in the Codex CLI and the ChatGPT
desktop/web apps (Work mode); the Codex IDE extension does not load plugins -
there, install individual skills instead by asking Codex to use
`$skill-installer` with
`https://github.com/omar-hanafy/biometric_vault/tree/main/agent_plugin/biometric-vault/skills/<skill-name>`.

Update later with `codex plugin marketplace upgrade biometric-vault`; remove
with `codex plugin remove biometric-vault`.

## Example prompts

- "Store our session token with biometric_vault so reads need Face ID, but
  background token rotation must not prompt."
- "Users on Android report StorageInvalidatedException after adding a
  fingerprint - writes still work. What do we do?"
- "Write flutter tests for our TokenStore that cover user cancellation and
  invalidation recovery."
- "We're on biometric_storage today; move us to biometric_vault without
  logging anyone out."

## Compatibility

- Skills target `biometric_vault` 1.x (written against 1.1.x) and inspect
  the consumer project before assuming versions or platforms.
- Clients: current Claude Code (plugins + marketplaces), OpenAI Codex CLI
  0.110+ (plugin system; skills also work standalone via `$skill-installer`).

## For maintainers

- One canonical plugin tree serves both clients: `.claude-plugin/plugin.json`
  and `.codex-plugin/plugin.json` next to a shared `skills/` directory;
  catalogs live at `/.claude-plugin/marketplace.json` (Claude) and
  `/.agents/plugins/marketplace.json` (Codex).
- Every skill is self-contained (its references live inside the skill
  directory) so per-skill installation keeps working.
- `dart tool/validate_agent_plugin.dart` (run in CI) enforces manifest
  syntax, kebab-case names, self-containment, and that the plugin version
  matches `pubspec.yaml` exactly.
- Behavioral eval cases live in `evals/` (`prompt.md` + `graders/criteria.md`
  per case) and run with `claude plugin eval agent_plugin/biometric-vault`.
- When package behavior changes, update the affected skill in the same PR;
  a future breaking package release must ship a dedicated versioned
  migration skill (see AGENTS.md at the repository root).
